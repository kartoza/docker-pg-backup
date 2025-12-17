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
source "${LIB_DIR}/restore.sh"
source "${LIB_DIR}/restore_s3.sh"
source "${LIB_DIR}/restore_file.sh"
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

log "Restore job started"

if [[ -n "${TARGET_DB}" ]]; then
  run_restore "${TARGET_ARCHIVE}" "${TARGET_DB}"
fi


log "Restore job finished"