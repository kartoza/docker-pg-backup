#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

############################################
# Paths
############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

############################################
# Source env variables
############################################

# Set dynamic date/time variables that should be fresh for each backup run
if [ -z "${MYDATE:-}" ]; then
  export MYDATE="$(date +%d-%B-%Y-%H-%M)"
fi

if [ -z "${MONTH:-}" ]; then
  export MONTH="$(date +%B)"
fi

if [ -z "${YEAR:-}" ]; then
  export YEAR="$(date +%Y)"
fi

if [ -z "${MYBASEDIR:-}" ]; then
  export MYBASEDIR="/${BUCKET:-backups}"
fi

if [ -z "${MYBACKUPDIR:-}" ]; then
  export MYBACKUPDIR="${MYBASEDIR}/${YEAR}/${MONTH}"
fi

# Create backup directories
mkdir -p "${MYBACKUPDIR}"
mkdir -p "${MYBASEDIR}"


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
if [[ "${CONSOLE_LOGGING:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  exec >> /proc/1/fd/1 2>&1
fi
############################################
# Traps
############################################
trap 'on_error $LINENO' ERR
trap 'on_terminate' SIGTERM SIGINT

############################################
# Init
############################################
init_logging


log "Backup job started at $(date +%d-%B-%Y-%H-%M)" true
COLORIZE=false

check_db_ready

############################################
# Backup execution
############################################
case "${STORAGE_BACKEND}" in
  S3)


    s3_init

    # Always refresh globals
    backup_globals

    # Database + optional table-level dumps
    backup_databases
    ;;
  FILE|file)


    backup_globals
    backup_databases
    ;;
  *)
    log "ERROR: Unknown STORAGE_BACKEND=${STORAGE_BACKEND}"

    exit 1
    ;;
esac

############################################
# Retention
############################################

run_retention

############################################
# Finish
############################################

log "Backup job completed successfully at $(date +%d-%B-%Y-%H-%M)" true

