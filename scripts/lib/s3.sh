#!/usr/bin/env bash

############################################
# Helpers
############################################
s3_log() {
  log "[S3] $*"
}

s3_init() {
  s3_log "Initializing S3 backend"

  if [[ -f "${EXTRA_CONFIG_DIR:-}/s3cfg" ]]; then
    cp "${EXTRA_CONFIG_DIR}/s3cfg" /root/.s3cfg
  else
    envsubst < /build_data/s3cfg > /root/.s3cfg
  fi

  s3cmd ls "s3://${BUCKET}" >/dev/null 2>&1 || s3cmd mb "s3://${BUCKET}"
}



s3_upload() {
  s3_log "Initializing S3 uploads"
  local gz_file="$1"
  local path="${gz_file#/}"
  local key="${path#${BUCKET}/}"
  local checksum_file="${gz_file}.sha256"


  [[ ! -f "${gz_file}" ]] && {
    s3_log "ERROR: Missing file ${gz_file}"
    return 1
  }

  s3_log "Uploading $(basename "${gz_file}") to s3://${BUCKET}"


  if retry 3 s3cmd put "${gz_file}" "s3://${BUCKET}/${key}"; then
    cleanup_backup "${gz_file}"
  else
    s3_log "ERROR: Failed to upload ${gz_file} after retries"
    return 1
  fi

  if [[ "${CHECKSUM_VALIDATION}" =~ [Tt][Rr][Uu][Ee] ]];then
    if [[ -f "${checksum_file}" ]];then
      if retry 3 s3cmd put "${checksum_file}" "s3://${BUCKET}/${key}"; then
        cleanup_backup "${gz_file}.sha256"
      else
        s3_log "ERROR: Failed to upload checksum ${checksum_file}"
        return 1
      fi
      cleanup_backup "${gz_file}.sha256"
    fi
  fi
  s3_log "S3 uploads completed"
}

