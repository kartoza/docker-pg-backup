#!/usr/bin/env bash

s3_init() {
  log "Initializing S3 backend"

  if [[ -f "${EXTRA_CONFIG_DIR:-}/s3cfg" ]]; then
    cp "${EXTRA_CONFIG_DIR}/s3cfg" /root/.s3cfg
  else
    envsubst < /build_data/s3cfg > /root/.s3cfg
  fi

  s3cmd ls "s3://${BUCKET}" >/dev/null 2>&1 || s3cmd mb "s3://${BUCKET}"
}

s3_upload() {
  local file="$1"

  gzip "${file}"
  s3cmd put "${file}.gz" "s3://${BUCKET}/"
  s3cmd put "${file}.sha256" "s3://${BUCKET}/"

  rm -f "${file}.gz"
}