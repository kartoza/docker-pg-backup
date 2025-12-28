#!/usr/bin/env bash

############################################
# Helpers
############################################
s3_log() {
  log "[S3] $*"
}

init_s3() {
  cat > /root/.s3cfg <<EOF
[default]
host_base = ${HOST_BASE}
host_bucket = ${HOST_BUCKET}
bucket_location = ${DEFAULT_REGION}
use_https = ${SSL_SECURE}
# Setup access keys
access_key =  ${ACCESS_KEY_ID}
secret_key = ${SECRET_ACCESS_KEY}
# Enable S3 v4 signature APIs
signature_v2 = False
EOF
}

s3_init() {
  s3_log "Initializing S3 backend"

  if [[ -f "${EXTRA_CONF_DIR:-}/s3cfg" ]]; then
    cp "${EXTRA_CONF_DIR}/s3cfg" /root/.s3cfg
  else
    init_s3
  fi

  s3cmd ls "s3://${BUCKET}" >/dev/null 2>&1 || s3cmd mb "s3://${BUCKET}"
}



s3_upload() {
  s3_log "Initializing S3 uploads"

  local gz_file="$1"

  [[ ! -f "${gz_file}" ]] && {
    s3_log "ERROR: Missing file ${gz_file}"
    return 1
  }

  # Normalize path → S3 key
  local path="${gz_file#/}"
  local gz_key="${path#${BUCKET}/}"
  local checksum_file="${gz_file}.sha256"
  local checksum_key="${gz_key}.sha256"

  s3_log "Uploading $(basename "${gz_file}") to s3://${BUCKET}/${gz_key}"

  # Upload gzip
  if ! retry 3 s3cmd put "${gz_file}" "s3://${BUCKET}/${gz_key}"; then
    s3_log "ERROR: Failed to upload ${gz_file}"
    return 1
  fi

  # Upload checksum (only if enabled and exists)
  if [[ "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]] && [[ -f "${checksum_file}" ]]; then
    s3_log "Uploading checksum $(basename "${checksum_file}")"

    if retry 3 s3cmd put "${checksum_file}" "s3://${BUCKET}/${checksum_key}"; then
      cleanup_backup "${checksum_file}"
    else
      s3_log "ERROR: Failed to upload checksum ${checksum_file}"
      return 1
    fi
  fi

  s3_log "S3 uploads completed"
}

