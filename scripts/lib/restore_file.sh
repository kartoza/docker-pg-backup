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
  [[ -z "${TARGET_ARCHIVE:-}" || ! -f "${TARGET_ARCHIVE}" ]] && {
    restore_filelog "ERROR: TARGET_ARCHIVE missing or invalid"
    exit 1
  }

  [[ -z "${TARGET_DB:-}" ]] && {
    restore_filelog "ERROR: TARGET_DB not set"
    exit 1
  }

  restore_filelog "File restore: archive=${TARGET_ARCHIVE} db=${TARGET_DB}"

  restore_recreate_db "${TARGET_DB}"
  restore_dump "${TARGET_ARCHIVE}" "${TARGET_DB}"
}