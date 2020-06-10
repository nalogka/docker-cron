#!/bin/sh

REPEAT_INTERVAL=7 # seconds
AVAILABLE_NETWORKS="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.NetworkID}}|{{end}}' $(hostname) | sed 's/|$//')"

docker info 2>/dev/null | grep 'Is Manager: true' >/dev/null || ( echo 'This container must be scheduled at the Swarm Manager node'; exit 1 )

exec 2>&1

function import_env {
  while read -r V; do [ -n "$V" ] && echo "$V" | grep -E '^\w+=' > /dev/null && export "$V"; done
}

function parse_tasks {
  SECTION_HEADER="# commands of $1\n"
  while IFS="=" read -r VAR VAL
  do
    echo "$VAL" | (
      read -r MIN HOUR DAY MONTH DOW COMMAND
      COMMAND="$(echo $COMMAND | envsubst)"
      echo -ne "$SECTION_HEADER"
      echo "$MIN $HOUR $DAY $MONTH $DOW curl -sf $COMMAND # $VAR"
    )
  SECTION_HEADER=""
  done
}

function rebuild {
  FORMAT='{{range $i, $item := .Spec.TaskTemplate.ContainerSpec.Env}}{{if $i}}{{"\n"}}{{end}}{{$item}}{{end}}'
  docker service ls --format '{{.Name}} {{.Replicas}}' | grep -v '/0 ' | while read -r SERVICE_NAME REPLICAS
  do
    docker service inspect --format='{{range .Spec.TaskTemplate.Networks}}{{.Target}}{{"\n"}}{{end}}' "$SERVICE_NAME" | grep -E "^($AVAILABLE_NETWORKS)$" >/dev/null \
      || continue
    docker service inspect --format="$FORMAT" "$SERVICE_NAME" | grep -v '^CRON_TASK_' | (
      import_env
      docker service inspect --format="$FORMAT" "$SERVICE_NAME" | grep '^CRON_TASK_' | parse_tasks "service $SERVICE_NAME"
    )
  done
}

function check_services_networks {
  while IFS=$(echo -e "\t") read -r ACTION SERVICE_NAME
  do
    if [ "$ACTION" != "remove " ]; then
      docker service inspect --format='{{range .Spec.TaskTemplate.Networks}}{{.Target}}{{"\n"}}{{end}}' "$SERVICE_NAME" | grep -E "^($AVAILABLE_NETWORKS)$" >/dev/null \
        && return 0
    else
      crontab -l | grep "^# commands of $SERVICE_NAME" >/dev/null \
        && return 0
    fi
  done
  return 1
}

function check_need_update {
  if [ -z "$1" ]; then
    echo "crontab update on cron service start"
    return 0
  else
    echo "$1" | check_services_networks \
      && echo "crontab update on $(echo "$1" | sed ':a;$!N;s/\n/, /;ta;s/\t/ /')" \
      && return 0
  fi
  return 1
}

function update {
  check_need_update "$1" && rebuild | crontab -
}

RECENTLY_UPDATED_AT="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"
update

while true
do
  NOW="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"
  EVENTS=$(
    docker events \
        --filter "type=service" \
        --format '{{.Action}} {{index .Actor.Attributes "updatestate.new"}}{{"\t"}}{{ .Actor.Attributes.name }}' \
        --since "$RECENTLY_UPDATED_AT" \
        --until "$NOW" \
      | tee /dev/stderr | grep -E '^(remove |create |update completed)'
  ) && update "$EVENTS"
  RECENTLY_UPDATED_AT="$NOW"
  sleep "$REPEAT_INTERVAL"
done
