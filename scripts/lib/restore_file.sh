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
  local format
  local workdir="/data/dump"

  format="$(get_dump_format "${DUMP_ARGS}")"

  restore_log "File restore requested"
  restore_log "Archive=${archive}"
  restore_log "Target DB=${TARGET_DB}"
  restore_log "Format=${format}"

  mkdir -p "${workdir}"

  ##########################################
  # DIRECTORY FORMAT (-Fd → tar.gz)
  ##########################################
  if [[ "${format}" == "directory" ]]; then
    [[ "${archive}" != *.tar.gz ]] && {
      restore_log "ERROR: Directory-format restore requires .tar.gz archive"
      return 1
    }
    filename=$(basename "${archive}")
    base_name="${filename%.tar.gz}"


    validate_checksum "${archive}" || return 1

    restore_log "Extracting directory dump"
    tar -xzf "${archive}" -C "${workdir}" || {
      restore_log "ERROR: Failed to extract ${archive}"
      return 1
    }

    restore_recreate_db "${TARGET_DB}"

    restore_dump "${workdir}/${base_name}" "${TARGET_DB}" || return 1

  ##########################################
  # CUSTOM FORMAT (-Fc → .dmp)
  ##########################################
  else
    validate_checksum "${archive}" || return 1

    restore_recreate_db "${TARGET_DB}"

    restore_dump "${archive}" "${TARGET_DB}" || return 1
  fi

  restore_log "File restore completed successfully for ${TARGET_DB}"
  return 0
}