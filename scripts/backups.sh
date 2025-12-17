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
source "/backup-scripts/pgenv.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/monitoring.sh"
source "${LIB_DIR}/db.sh"
source "${LIB_DIR}/encryption.sh"
source "${LIB_DIR}/s3.sh"
source "${LIB_DIR}/retention.sh"
source "${LIB_DIR}/utils.sh"

############################################
# Traps
############################################
trap 'on_error $LINENO' ERR
trap 'on_terminate' SIGTERM SIGINT

############################################
# Init
############################################
init_logging

log "Backup job started"

check_db_ready

############################################
# Backup execution
############################################
case "${STORAGE_BACKEND}" in
  S3)
    ENABLE_S3_BACKUP=true

    s3_init

    # Always refresh globals
    backup_globals

    # Database + optional table-level dumps
    backup_databases
    ;;
  FILE|file)
    ENABLE_S3_BACKUP=false

    backup_globals
    backup_databases
    ;;
  *)
    log "ERROR: Unknown STORAGE_BACKEND=${STORAGE_BACKEND}"
    notify_monitoring "failure"
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
log "Backup job completed successfully"
notify_monitoring "success" || true
exit 0