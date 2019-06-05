FROM docker:latest AS docker

FROM alpine:latest
LABEL maintainer="Anton Tyutin <anton@tyutin.ru>"

ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8

COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
RUN apk --no-cache add tzdata \
    && cp /usr/share/zoneinfo/Etc/UTC /etc/localtime \
    && echo "UTC" > /etc/timezone \
    && apk del tzdata

RUN apk --no-cache add curl dcron runit \
    && echo -e "#!/bin/sh\\n\\nsed '1d; s/Subject: cron for user root docker exec /# /; /^\\s*\$/d' >/proc/1/fd/1" >/tmp/cron-logger \
    && chmod 755 /tmp/cron-logger \
    \
    # runit supervisor setup
    && mkdir -p /supervisor/crond \
      && echo -e '#!/bin/sh\n\nexec crond -f -M/tmp/cron-logger' > /supervisor/crond/run \
      && chmod 755 /supervisor/crond/run \
    && mkdir -p /supervisor/docker-listener \
    && true

COPY docker-listener.sh /supervisor/docker-listener/run

LABEL "com.nalogka.cron"=true

ENV DOCKER_HOST="unix:///tmp/docker.sock"

CMD ["/sbin/runsvdir", "-P", "/supervisor"]
