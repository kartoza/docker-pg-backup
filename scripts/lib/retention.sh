#!/usr/bin/env bash
set -euo pipefail

retention_log() {
  log "[RETENTION] $*"
}

############################################
# Entry point
############################################
run_retention() {
  if [[ "${REMOVE_BEFORE}" -le 0 || -n "${TARGET_ARCHIVE:-}" ]]; then
    retention_log "Either REMOVE_BEFORE=${REMOVE_BEFORE} is set to 0 or TARGET_ARCHIVE=${TARGET_ARCHIVE:-} is set, so no retention will run"
    return 0
  fi

  retention_log "Starting retention"
  retention_log "REMOVE_BEFORE=${REMOVE_BEFORE}d MIN_SAVED_FILE=${MIN_SAVED_FILE} CONSOLIDATE_AFTER=${CONSOLIDATE_AFTER}d"

  run_local_retention

  if [[ "${ENABLE_S3_BACKUP}" =~ [Tt][Rr][Uu][Ee] ]]; then
    retention_log "Running S3 retention"
    run_s3_retention
  fi

  retention_log "Retention finished"
}

############################################
# Local retention
############################################
run_local_retention() {
  if (( CONSOLIDATE_AFTER > 0 )); then
    consolidate_backups
  fi

  expire_old_backups
}

############################################
# Sub-daily consolidation
############################################
consolidate_backups() {
  local consolidate_minutes=$(( CONSOLIDATE_AFTER * 24 * 60 ))

  retention_log "Consolidating backups older than ${CONSOLIDATE_AFTER} days"

  mapfile -t files_with_time < <(
    find "${MYBASEDIR}" -type f \
      -mmin "+${consolidate_minutes}" \
      ! -name "globals.sql" \
      -printf "%T@ %p\n" | sort -n
  )

  declare -A keep_map

  for entry in "${files_with_time[@]}"; do
    file="${entry#* }"
    fname="$(basename "$file")"

    key="$(sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\).*/\1/p' <<< "$fname")"
    [[ -z "$key" ]] && continue
    [[ -n "${keep_map[$key]:-}" ]] && continue

    keep_map["$key"]="$file"
  done

  for entry in "${files_with_time[@]}"; do
    file="${entry#* }"
    fname="$(basename "$file")"

    key="$(sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\).*/\1/p' <<< "$fname")"
    [[ -z "$key" ]] && continue
    [[ "${keep_map[$key]}" == "$file" ]] && continue

    delete_file "$file" "consolidation"
  done
}

############################################
# Expiry retention (FIXED)
############################################
expire_old_backups() {
  local minutes=$(( REMOVE_BEFORE * 24 * 60 ))

  # Newest → oldest
  mapfile -t all_files < <(
    find "${MYBASEDIR}" -type f ! -name "globals.sql" \
      -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-
  )

  # Files older than REMOVE_BEFORE
  mapfile -t old_files < <(
    find "${MYBASEDIR}" -type f ! -name "globals.sql" \
      -mmin "+${minutes}" \
      -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-
  )

  retention_log "Found ${#old_files[@]} backups older than ${REMOVE_BEFORE} days"

  # Protect newest MIN_SAVED_FILE backups
  declare -A protected
  for ((i=0; i<MIN_SAVED_FILE && i<${#all_files[@]}; i++)); do
    protected["${all_files[$i]}"]=1
  done

  (( MIN_SAVED_FILE > 0 )) && \
    retention_log "Protecting ${MIN_SAVED_FILE} newest backups"

  # Delete old backups unless protected
  for file in "${old_files[@]}"; do
    if [[ -n "${protected[$file]:-}" ]]; then
      retention_log "Keeping ${file} (protected by MIN_SAVED_FILE)"
      continue
    fi
    delete_file "${file}" "expiry"
  done
}

############################################
# Safe delete
############################################
delete_file() {
  local file="$1"
  local reason="$2"

  if [[ "${CLEANUP_DRY_RUN}" == "true" ]]; then
    retention_log "[DRY-RUN] Would delete ${file} (${reason})"
  else
    retention_log "Deleting ${file} (${reason})"
    rm -f "${file}"
  fi
}

############################################
# S3 retention
############################################
run_s3_retention() {
  retention_log "Running S3 retention on ${S3_BUCKET}"

  if ! s3cmd ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
    retention_log "Bucket ${S3_BUCKET} not accessible"
    return 0
  fi

  clean_s3_bucket "${S3_BUCKET}" "${REMOVE_BEFORE}"
}

clean_s3_bucket() {
  local bucket="$1"
  local days="$2"
  local cutoff
  cutoff=$(date -d "${days} days ago" +%s)

  s3cmd ls "s3://${bucket}" --recursive | while read -r line; do
    local date path ts

    date="$(awk '{print $1}' <<< "$line")"
    path="$(awk '{print $4}' <<< "$line")"
    [[ -z "$path" ]] && continue

    ts=$(date -d "$date" +%s 2>/dev/null || echo 0)

    if (( ts > 0 && ts < cutoff )); then
      if [[ "${CLEANUP_DRY_RUN}" == "true" ]]; then
        retention_log "[DRY-RUN] Would delete S3 object ${path}"
      else
        log "Deleting S3 object ${path}"
        s3cmd del "${path}"
      fi
    fi
  done
}