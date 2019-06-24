FROM docker:latest AS docker

FROM alpine:latest
LABEL maintainer="Anton Tyutin <anton@tyutin.ru>"

ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8

COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker

RUN apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/Etc/UTC /etc/localtime \
    && echo "UTC" > /etc/timezone \
    && apk del tzdata

RUN apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/

RUN apk add --no-cache curl dcron runit \
    && echo -e "#!/bin/sh\\n\\nsed '1d; 2s/Subject: cron for user root /# /; 3d; 4,\$s/^/  | /' >/proc/1/fd/1" >/tmp/cron-logger \
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
