#!/usr/bin/env bash

function die { echo "$@"; exit 1; }

IMAGES=()
IMAGE_IDX=0

PULL_OPT="--pull"
for DOCKERFILE in Dockerfile
do
  TAG="cr.yandex/crpsernav4j2pmc2qpv1/cron:stable"
  docker build $PULL_OPT -f "$DOCKERFILE" -t "$TAG" . || die "Image build failed"
  IMAGES[$IMAGE_IDX]="$TAG"; ((IMAGE_IDX++));
  PULL_OPT=""
done

for TAG in ${IMAGES[@]}
do
  docker push "$TAG" || die "Can't push image"
done
