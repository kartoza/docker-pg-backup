#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

############################################
# Helpers
############################################
restore_log() {
  log "[DB Restore] $*"
}


############################################
# Restore dispatcher
############################################
run_restore() {
  restore_log "Starting restore (backend=${STORAGE_BACKEND})"

  case "${STORAGE_BACKEND}" in
    S3|s3)
      s3_restore_init
      s3_restore "$@" "$@"
      ;;
    FILE|file)
      file_restore "$@" "$@"
      ;;
    *)
      restore_log "ERROR: Unknown STORAGE_BACKEND=${STORAGE_BACKEND}"
      exit 1
      ;;
  esac

  restore_log "Restore completed successfully"
}