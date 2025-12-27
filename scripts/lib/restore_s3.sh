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
    init_s3
  fi
}

############################################
# Resolve backup from DATE or DATETIME
############################################
resolve_backup_from_date() {
  local s3_dir="$1"

  local want_datetime="${TARGET_ARCHIVE_DATETIME:-}"
  local want_date="${TARGET_ARCHIVE_DATE_ONLY:-}"

  local candidates=()

  ############################################
  # Walk S3 directory ONCE
  ############################################
  while read -r _ _ _ path; do
    [[ -z "$path" || "$path" == *"globals.sql"* ]] && continue

    fname="$(basename "$path")"

    # Must look like a dump
    [[ "$fname" != ${DUMPPREFIX}_* ]] && continue
    [[ "$fname" =~ \.(dmp\.gz|dir\.tar\.gz)$ ]] || continue

    # Strip extension
    base="${fname%.dmp.gz}"
    base="${base%.dir.tar.gz}"

    datetime_part="${base##*.}"   # DD-Month-YYYY-HH-MM

    ##########################################
    # DATETIME match (YYYY-MM-DD-HH-MM)
    ##########################################
    if [[ -n "$want_datetime" ]]; then
      want_fmt="$(date -d "${want_datetime:0:10} ${want_datetime:11:2}:${want_datetime:14:2}" '+%d-%B-%Y-%H-%M')"

      if [[ "$datetime_part" == "$want_fmt" ]]; then
        echo "${path#s3://${BUCKET}/}"
        return 0
      fi
      continue
    fi

    ##########################################
    # DATE-only match (YYYY-MM-DD)
    ##########################################
    if [[ -n "$want_date" ]]; then
      IFS='-' read -r day month year hour min <<< "$datetime_part" || continue
      file_date="$(date -d "${day} ${month} ${year}" '+%Y-%m-%d' 2>/dev/null || true)"

      [[ "$file_date" == "$want_date" ]] && candidates+=("$path")
    fi

  done < <(s3cmd ls "s3://${BUCKET}/${s3_dir}/" 2>/dev/null || true)

  ############################################
  # Resolution
  ############################################
  (( ${#candidates[@]} == 0 )) && return 0

  # Single file → use it
  (( ${#candidates[@]} == 1 )) && {
    echo "${candidates[0]#s3://${BUCKET}/}"
    return 0
  }

  ############################################
  # Multiple files → pick latest HH-MM
  ############################################
  local best_ts=0
  local best_key=""

  for path in "${candidates[@]}"; do
    fname="$(basename "$path")"

    base="${fname%.dmp.gz}"
    base="${base%.dir.tar.gz}"
    datetime_part="${base##*.}"

    IFS='-' read -r day month year hour min <<< "$datetime_part" || continue
    ts="$(date -d "${day} ${month} ${year} ${hour}:${min}" '+%s' 2>/dev/null || echo 0)"

    (( ts > best_ts )) && {
      best_ts="$ts"
      best_key="$path"
    }
  done

  [[ -n "$best_key" ]] && echo "${best_key#s3://${BUCKET}/}"
}
############################################
# S3 restore
############################################
s3_restore() {
  local input_date="$1"
  local target_db="$2"

  [[ -z "$target_db" ]] && {
    restore_s3log "ERROR: TARGET_DB is required"
    return 1
  }

  restore_s3log "S3 restore requested: date='${input_date:-AUTO}' target_db=${target_db}"

  local backup_key=""
  local checksum_key=""
  local workdir="/data/dump"

  mkdir -p "$workdir"

  ############################################
  # 1. Explicit archive override
  ############################################
  if [[ -n "${TARGET_ARCHIVE:-}" ]]; then
    backup_key="$(normalize_archive "${TARGET_ARCHIVE}")"
    [[ "$backup_key" != *.gz ]] && backup_key="${backup_key}.gz"

    restore_s3log "Using TARGET_ARCHIVE override: ${backup_key}"

  ############################################
  # 2. Date-based resolution
  ############################################
  else
    [[ -z "$input_date" ]] && {
      restore_s3log "ERROR: Date required when TARGET_ARCHIVE not set"
      return 1
    }

    local date_part="${input_date:0:10}"
    local year month

    year="$(date -d "$date_part" +%Y)"
    month="$(date -d "$date_part" +%B)"

    local s3_dir="${year}/${month}"

    restore_s3log "Resolving backup from s3://${BUCKET}/${s3_dir}"

    backup_key="$(resolve_backup_from_date "$s3_dir")"

    [[ -z "$backup_key" ]] && {
      restore_s3log "ERROR: No backup found for ${input_date}"
      return 1
    }
  fi

  checksum_key="${backup_key}.sha256"

  restore_s3log "Resolved archive: s3://${BUCKET}/${backup_key}"

  ############################################
  # 3. Download archive (+ checksum)
  ############################################
  s3cmd get "s3://${BUCKET}/${backup_key}" "${workdir}/$(basename "$backup_key")"

  if [[ "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    restore_s3log "Downloading checksum"
    s3cmd get "s3://${BUCKET}/${checksum_key}" "${workdir}/$(basename "$checksum_key")"
    validate_checksum "${workdir}/$(basename "$checksum_key")" || return 1
  fi

  ############################################
  # 4. Restore
  ############################################
  local archive="${workdir}/$(basename "$backup_key")"

  if [[ "$archive" == *.tar.gz ]]; then
    tar -xzf "$archive" -C "$workdir"
    restore_recreate_db "$target_db"
    restore_dump "${archive%.tar.gz}" "$target_db"
  else
    gunzip -f "$archive"
    restore_recreate_db "$target_db"
    restore_dump "${archive%.gz}" "$target_db"
  fi

  restore_s3log "Restore completed successfully for ${target_db}"
}