#!/usr/bin/env bash
set -euo pipefail

############################################
# Logging
############################################

retention_log() {
  log "[RETENTION] $*"
}

############################################
# Entry point
############################################
run_retention() {
  : "${TARGET_ARCHIVE:=}"

  if [[ "${REMOVE_BEFORE}" -le 0 || -n "${TARGET_ARCHIVE}" ]]; then
    retention_log \
      "Either REMOVE_BEFORE=${REMOVE_BEFORE} is set to 0 or TARGET_ARCHIVE=${TARGET_ARCHIVE} is set, so no retention will run"
    return 0
  fi

  retention_log "Starting retention"
  retention_log \
    "REMOVE_BEFORE=${REMOVE_BEFORE}d MIN_SAVED_FILE=${MIN_SAVED_FILE} CONSOLIDATE_AFTER=${CONSOLIDATE_AFTER}d"



  if [[ "${STORAGE_BACKEND}" == 'S3' ]]; then

    run_s3_retention
  else
    run_local_retention
  fi

  retention_log "Retention finished"
}

############################################
# Local retention
############################################
run_local_retention() {
  (( CONSOLIDATE_AFTER > 0 )) && consolidate_backups
  expire_old_backups
}

############################################
# Local consolidation
############################################
consolidate_backups() {
  local consolidate_minutes=$(( CONSOLIDATE_AFTER * 24 * 60 ))

  retention_log "Consolidating local backups older than ${CONSOLIDATE_AFTER} days"

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

    key="$(sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\|gz\).*/\1/p' <<< "$fname")"
    [[ -z "$key" || -n "${keep_map[$key]:-}" ]] && continue

    keep_map["$key"]="$file"
  done

  for entry in "${files_with_time[@]}"; do
    file="${entry#* }"
    fname="$(basename "$file")"

    key="$(sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\|gz\).*/\1/p' <<< "$fname")"
    [[ -z "$key" ]] && continue
    [[ "${keep_map[$key]}" == "$file" ]] && continue

    delete_file "$file" "consolidation"
  done
}

############################################
# Local expiry (MIN_SAVED_FILE aware)
############################################
expire_old_backups() {
  local minutes=$(( REMOVE_BEFORE * 24 * 60 ))

  mapfile -t all_files < <(
    find "${MYBASEDIR}" -type f ! -name "globals.sql" \
      -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-
  )

  mapfile -t old_files < <(
    find "${MYBASEDIR}" -type f ! -name "globals.sql" \
      -mmin "+${minutes}" \
      -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-
  )

  retention_log "Found ${#old_files[@]} backups older than ${REMOVE_BEFORE} days"

  declare -A protected
  for ((i=0; i<MIN_SAVED_FILE && i<${#all_files[@]}; i++)); do
    protected["${all_files[$i]}"]=1
  done

  (( MIN_SAVED_FILE > 0 )) &&
    retention_log "Protecting ${MIN_SAVED_FILE} newest backups"

  for file in "${old_files[@]}"; do
    [[ -n "${protected[$file]:-}" ]] && continue
    delete_file "$file" "expiry"
  done
}

############################################
# Safe delete
############################################
delete_file() {
  local file="$1"
  local reason="$2"

  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
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
  : "${BUCKET:?BUCKET must be set when STORAGE_BACKEND=S3}"
  : "${REMOVE_BEFORE:=0}"
  : "${CONSOLIDATE_AFTER:=0}"

  retention_log "Running S3 retention on ${BUCKET}"


  if s3cmd ls "s3://${BUCKET}" >/dev/null 2>&1; then
    :
  else
    retention_log "Bucket ${BUCKET} not accessible"
    return 0
  fi

  s3_expire_objects

  if (( CONSOLIDATE_AFTER > 0 )); then
    s3_consolidate_objects
  fi
}

############################################
# S3 expiry
############################################
s3_expire_objects() {
  local cutoff
  cutoff=$(date -d "${REMOVE_BEFORE} days ago" +%s)

  retention_log "Expiring S3 backups older than ${REMOVE_BEFORE} days"

  while read -r _ _ _ path; do
    [[ -z "${path:-}" || "$path" == *"globals.sql"* ]] && continue

    fname="$(basename "$path")"
    ts=$(extract_ts_from_filename "$fname")

    (( ts == 0 || ts >= cutoff )) && continue

    if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
      retention_log "[DRY-RUN] Would delete S3 object ${path}"
    else
      retention_log "Deleting S3 object ${path} (expiry)"
      s3cmd del "${path}"
    fi
  done < <(s3cmd ls "s3://${BUCKET}" --recursive || true)
}

############################################
# S3 consolidation
############################################
s3_consolidate_objects() {
  local cutoff
  cutoff=$(date -d "${CONSOLIDATE_AFTER} days ago" +%s)

  retention_log "Consolidating S3 backups older than ${CONSOLIDATE_AFTER} days"

  declare -A keep_map

  # First pass: decide what to keep
  while read -r _ date _ path; do
    [[ -z "${path}" || "$path" == *"globals.sql"* ]] && continue

    ts=$(date -d "${date}" +%s 2>/dev/null || echo 0)
    (( ts == 0 || ts >= cutoff )) && continue

    fname="$(basename "${path}")"
    key="$(sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\|gz\).*/\1/p' <<< "${fname}")"
    [[ -z "${key}" || -n "${keep_map[$key]:-}" ]] && continue

    keep_map["$key"]="${path}"
  done < <(s3cmd ls "s3://${BUCKET}" --recursive | sort || true)

  # Second pass: delete everything else
  while read -r _ date _ path; do
    [[ -z "${path}" || "$path" == *"globals.sql"* ]] && continue

    ts=$(date -d "${date}" +%s 2>/dev/null || echo 0)
    (( ts == 0 || ts >= cutoff )) && continue

    fname="$(basename "${path}")"
    key="$(sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\|gz\).*/\1/p' <<< "${fname}")"

    [[ -z "${key}" || "${keep_map[$key]:-}" == "${path}" ]] && continue

    if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
      retention_log "[DRY-RUN] Would delete S3 object ${path} (consolidation)"
    else
      retention_log "Deleting S3 object ${path} (consolidation)"
      s3cmd del "${path}"
    fi
  done < <(s3cmd ls "s3://${BUCKET}" --recursive || true)
}