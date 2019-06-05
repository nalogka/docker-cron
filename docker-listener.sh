#!/bin/sh

exec 2>&1

function rebuild {
  # non service task's containers
  FORMAT='{{range $i, $var := .Config.Env}}{{if $i}}{{"\n"}}{{end}}{{$var}}{{end}}'
  docker ps -f "is-task=false" -f "status=running" --format '{{.ID}} {{.Names}}' | while read -r ID CONTAINER_NAME
  do
    SECTION_HEADER="# commands of container $CONTAINER_NAME\n"
    docker inspect --format "$FORMAT" "$ID" | grep 'CRON_TASK_' | while IFS="=" read -r VAR VAL
    do
      echo "$VAL" | (
        read -r MIN HOUR DAY MONTH DOW COMMAND
        echo -ne "$SECTION_HEADER"
        echo "$MIN $HOUR $DAY $MONTH $DOW curl -sf $COMMAND"
      )
      SECTION_HEADER=""
    done
  done
  # service task's containers
  FORMAT='{{range $i, $item := .Spec.TaskTemplate.ContainerSpec.Env}}{{if $i}}{{"\n"}}{{end}}{{$item}}{{end}}'
  docker service ls --format '{{.Name}} {{.Replicas}}' | grep -v ' 0/' | while read -r SERVICE_NAME REPLICAS
  do
    SECTION_HEADER="# commands of service $SERVICE_NAME\n"
    docker service inspect --format="$FORMAT" "$SERVICE_NAME" | grep 'CRON_TASK_' | while IFS="=" read -r VAR VAL
    do
      echo "$VAL" | (
        read -r MIN HOUR DAY MONTH DOW COMMAND
        echo -ne "$SECTION_HEADER"
        echo "$MIN $HOUR $DAY $MONTH $DOW curl -sf $COMMAND"
      )
      SECTION_HEADER=""
    done
  done
}

function wait_stop {
  while docker ps --no-trunc -f "status=running" --format '{{.ID}}' | grep "$1" >/dev/null; do sleep 0.1; done
}

function update {
  rebuild | crontab -
  echo 'crontab updated'
}

update
RECENTLY_UPDATED_AT="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"

while true
do
  NOW="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"
  ( docker events \
      --filter "type=service" \
      --format "{{.Action}} {{index .Actor.Attributes \"updatestate.new\"}}" \
      --since "$RECENTLY_UPDATED_AT" \
      --until "$NOW" \
    | grep -E '^(remove |create |update completed)$' >/dev/null \
  || docker events --filter="type=container" \
      --format "{{if index .Actor.Attributes \"com.docker.swarm.task.id\"}}!{{end}}{{.Status}}" \
      --since "$RECENTLY_UPDATED_AT" \
      --until "$NOW" \
    | grep -E '^(start|die)$' >/dev/null \
  ) && update
  RECENTLY_UPDATED_AT="$NOW"
  sleep 5
done
