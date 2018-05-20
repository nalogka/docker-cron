#!/bin/bash

exec 2>&1

function rebuild {
  FORMAT_ENV='{{range $idx, $var := .Config.Env}}{{if $idx}}{{"\n"}}{{end}}{{$var}}{{end}}'
  docker ps -f "status=running" --format '{{.ID}} {{.Names}}' | while read -r ID CONTAINER_NAME
  do
    SECTION_HEADER="# commands of $CONTAINER_NAME\n"
    docker inspect --format "$FORMAT_ENV" "$ID" | grep 'CRON_TASK_' | while IFS="=" read -r VAR VAL
    do
      read -r MIN HOUR DAY MONTH DOW COMMAND <<< "$VAL"
      echo -ne "$SECTION_HEADER"
      echo "$MIN $HOUR $DAY $MONTH $DOW docker exec $ID $COMMAND"
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

docker events --filter "type=container" --format "{{.ID}} {{.Status}}" | while read -r ID STATUS
do
  case "$STATUS" in
    start) echo "$ID is running" && update ;;
    die)   wait_stop "$ID" && echo "$ID has stopped" && update ;;
  esac
done
