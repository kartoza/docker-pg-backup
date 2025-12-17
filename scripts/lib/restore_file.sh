#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

############################################
# Helpers
############################################
restore_filelog() {
  log "[DB File Restore ] $*"
}


############################################
# File restore
############################################
file_restore() {
  [[ -z "${TARGET_ARCHIVE:-}" ]] && {
    restore_log "ERROR: TARGET_ARCHIVE required"
    return 1
  }

  [[ -z "${TARGET_DB:-}" ]] && {
    restore_log "ERROR: TARGET_DB required"
    return 1
  }

  local archive="${TARGET_ARCHIVE}"

  validate_checksum "${archive}" || return 1

  restore_recreate_db "${TARGET_DB}"
  restore_dump "${archive}" "${TARGET_DB}"

  restore_log "File restore completed for ${TARGET_DB}"
}
