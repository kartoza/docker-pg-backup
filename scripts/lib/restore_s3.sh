#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

############################################
# Helpers
############################################
restore_s3log() {
  log "[DB S3 Restore ] $*"
}


############################################
# S3 config
############################################
s3_restore_init() {
  restore_s3log "Initializing S3 restore configuration"

  if [[ -f "${EXTRA_CONFIG_DIR:-}/s3cfg" ]]; then
    cp -f "${EXTRA_CONFIG_DIR}/s3cfg" /root/.s3cfg
  else
    envsubst < /build_data/s3cfg > /root/.s3cfg
  fi
}

############################################
# S3 restore
############################################
s3_restore() {
  local input_date="$1"
  local target_db="$2"

  [[ -z "${target_db}" ]] && {
    restore_s3log "ERROR: target_db is required"
    return 1
  }

  restore_s3log "S3 restore requested: date='${input_date:-AUTO}' db=${target_db}"

  local backup_key=""
  local checksum_key=""
  local workdir="/data/dump"

  mkdir -p "${workdir}"

  ############################################
  # 1. ARCHIVE_FILENAME override (authoritative)
  ############################################
  if [[ -n "${TARGET_ARCHIVE:-}" ]]; then
    filename="$(normalize_archive "${TARGET_ARCHIVE}")"
    if [[ "$filename" != *.gz ]]; then
      backup_key="${filename}.gz"
    else
      backup_key="${filename}"
    fi

    restore_s3log "Using ARCHIVE_FILENAME override: ${backup_key}"

  ############################################
  # 2. Date-based resolution
  ############################################
  else
    [[ -z "${input_date}" ]] && {
      restore_s3log "ERROR: date required when ARCHIVE_FILENAME not set"
      return 1
    }

    local date_part hour minute mydate month year
    date_part="${input_date:0:10}"

    month="$(date -d "${date_part}" +%B)"
    year="$(date -d "${date_part}" +%Y)"

    local s3_dir="${year}/${month}"

    # Exact timestamp YYYY-MM-DD-HH-MM
    if [[ "${input_date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
      hour="${input_date:11:2}"
      minute="${input_date:14:2}"
      mydate="$(date -d "${date_part}" +%d-%B-%Y)-${hour}-${minute}"
      backup_key="${s3_dir}/${DUMPPREFIX}_${target_db}.${mydate}.dmp.gz"

    # Latest-of-day
    else
      mydate="$(date -d "${date_part}" +%d-%B-%Y)"
      restore_s3log "Finding latest backup for ${date_part}"

      backup_key="$(
        s3cmd ls "s3://${BUCKET}/${s3_dir}/" \
          | awk '{print $4}' \
          | grep -F "${DUMPPREFIX}_${target_db}.${mydate}-" \
          | grep '\.dmp\.gz$' \
          | sort -r | head -n1
      )"

      backup_key="${backup_key#s3://${BUCKET}/}"
    fi
  fi

  [[ -z "${backup_key}" ]] && {
    restore_s3log "ERROR: Could not resolve backup archive"
    return 1
  }

  checksum_key="${backup_key}.sha256"

  restore_s3log "Resolved archive: s3://${BUCKET}/${backup_key}"

  ############################################
  # 3. Download archive (+ checksum)
  ############################################
  s3cmd get "s3://${BUCKET}/${backup_key}" "${workdir}/${backup_key}"

  if [[ "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    restore_s3log "Downloading checksum for ${target_db} "
    s3cmd get "s3://${BUCKET}/${checksum_key}" "${workdir}/${checksum_key}"
    validate_checksum "${workdir}/${checksum_key}"  || return 1
    restore_s3log "Checksum download and validation completed successfully for ${target_db}"
  fi
  if [[ ${backup_key} == *.tar.gz ]];then
    tar -xzf "${workdir}/${backup_key}" -C "${workdir}" || {
      restore_log "ERROR: Failed to extract ${backup_key}"
      return 1
    }
    restore_recreate_db "${target_db}"
    restore_dump "${workdir}/${backup_key%.tar.gz}" "${target_db}"
  else
    gunzip -f "${workdir}/${backup_key}"
    restore_recreate_db "${target_db}"
    restore_dump "${workdir}/${backup_key%.gz}" "${target_db}"
  fi


  restore_s3log "Restore completed successfully for ${target_db}"


}