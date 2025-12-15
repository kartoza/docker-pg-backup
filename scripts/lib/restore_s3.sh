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

  [[ -z "${input_date}" || -z "${target_db}" ]] && {
    restore_s3log "ERROR: restore requires <date> <db>"
    exit 1
  }

  restore_s3log "S3 restore requested: date=${input_date} db=${target_db}"

  local date_part hour minute mydate month year
  local backup_url

  if [[ "${input_date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
    date_part="${input_date%-*-*}"
    hour="${input_date#*-*-*-}"
    hour="${hour%-*}"
    minute="${input_date##*-}"
    mydate="$(date -d "${date_part}" +%d-%B-%Y)-${hour}-${minute}"
  else
    date_part="${input_date}"
    mydate="$(date -d "${date_part}" +%d-%B-%Y)"
  fi

  month="$(date -d "${date_part}" +%B)"
  year="$(date -d "${date_part}" +%Y)"

  MYBASEDIR="/${BUCKET}"
  MYBACKUPDIR="${MYBASEDIR}/${year}/${month}"

  backup_url="s3://${MYBACKUPDIR}/${DUMPPREFIX}_${target_db}.${mydate}.dmp.gz"

  if [[ ! "${input_date}" =~ -[0-9]{2}-[0-9]{2}$ ]]; then
    restore_s3log "Finding latest backup for ${date_part}"
    backup_url="$(s3cmd ls "s3://${MYBACKUPDIR}/" \
      | grep -F "${DUMPPREFIX}_${target_db}.${mydate}-" \
      | awk '{print $4}' \
      | sort -r | head -n1)"
    checksum_url="${backup_url}.sha256"
  fi

  [[ -z "${backup_url}" ]] && {
    restore_s3log "ERROR: No backup found"
    exit 1
  }

  restore_s3log "Using backup ${backup_url}"

  mkdir -p /data/dump
  if [[ -n "${backup_url}" ]]; then
    s3cmd get "${backup_url}" "/data/dump/${target_db}.dmp.gz"
  else
    restore_s3log "No backup URL provided, skipping restore."
  fi


  if [[ "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]];then
    if [[ -n "${checksum_url}" ]]; then
       s3cmd get "${checksum_url}" "/data/dump/${target_db}.dmp.sha256"
    else
       restore_s3log "No checksum URL provided, skipping restore."
    fi
  fi

  if [[ -f "/data/dump/${target_db}.dmp.gz" ]];then
    gunzip -f "/data/dump/${target_db}.dmp.gz"
    restore_recreate_db "${target_db}"
    restore_dump "/data/dump/${target_db}.dmp" "${target_db}"
  fi


}