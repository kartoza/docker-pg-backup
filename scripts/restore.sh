#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit



############################################
# Paths
############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

############################################
# Load libraries
############################################

configure_sources() {
  # Always source the environment file first
  [[ -f /backup-scripts/pgenv.sh ]] && source /backup-scripts/pgenv.sh

  # List of library modules to source
  local libs=(
    logging
    monitoring
    db
    encryption
    s3
    retention
    restore
    restore_s3
    restore_file
    utils
  )

  for lib in "${libs[@]}"; do
    local file="${LIB_DIR}/${lib}.sh"
    if [[ -f "$file" ]]; then
      source "$file"
    else
      echo "Warning: missing library $file" >&2
    fi
  done
}

configure_sources


############################################
# Traps
############################################
trap 'on_error $LINENO' ERR
trap 'on_terminate' SIGTERM SIGINT

############################################
# Init
############################################
init_logging

log "Restore job started"

if [ -z "${DBLIST:-}" ]; then

  until PGPASSWORD=${POSTGRES_PASS} pg_isready ${PG_CONN_PARAMETERS}; do
    sleep 1
  done
  export DBLIST=$(PGPASSWORD=${POSTGRES_PASS} psql ${PG_CONN_PARAMETERS} -l | awk '$1 !~ /[+(|:]|Name|List|template|postgres/ {print $1}')
  log "Database list is::  ${DBLIST}"
fi

if [[ -n "${TARGET_DB}" && -n "${TARGET_ARCHIVE:-}" ]]; then
  run_restore "${TARGET_ARCHIVE:-}" "${TARGET_DB}"

elif [[ -n "${TARGET_DB}" && -n "${TARGET_ARCHIVE_DATE_ONLY:-}" ]]; then
  run_restore "${TARGET_ARCHIVE_DATE_ONLY:-}" "${TARGET_DB}"

elif [[ -n "${TARGET_DB}" && -n "${TARGET_ARCHIVE_DATETIME:-}" ]]; then
  run_restore "${TARGET_ARCHIVE_DATETIME:-}" "${TARGET_DB}"

else
  echo "Error: TARGET_DB has a value ${TARGET_DB} and archive has a value ${TARGET_ARCHIVE:-},   must be set"
  exit 1
fi

log "Restore job finished"