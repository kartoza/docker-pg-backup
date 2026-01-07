#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

############################################
# Helpers
############################################
restore_filelog() {
  log "[DB File Restore ] $*"
}

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------
: "${MONTH:=$(date +%B)}"
: "${YEAR:=$(date +%Y)}"
: "${MYBASEDIR:=/${BUCKET:-backups}}"
: "${MYBACKUPDIR:=${MYBASEDIR}/${YEAR}/${MONTH}}"


############################################
# File restore
############################################
file_restore() {
  local decrypt_folder="${MYBACKUPDIR}"


  [[ -z "${TARGET_DB:-}" ]] && {
    restore_log "ERROR: TARGET_DB required"
    return 1
  }

  local archive="${TARGET_ARCHIVE:-}"

  ##########################################
  # Resolve archive from date/datetime
  ##########################################
  if [[ -z "${archive}" ]]; then
    restore_log "Resolving local backup from date/datetime"
    archive="$(resolve_local_backup_from_date "${decrypt_folder}")" || return 1
  fi

  ##########################################
  # Validate archive
  ##########################################
  if [[ ! -f "${archive}" ]]; then
    restore_log "ERROR: Archive ${archive} not found"
    return 1
  fi

  ##########################################
  # Load metadata (BEFORE any extraction)
  ##########################################
  load_restore_metadata "${archive}" || return 1

  ##########################################
  # Determine dump format
  ##########################################
  local format
  format="$(get_dump_format "${DUMP_ARGS}")"

  restore_log "File restore requested"
  restore_log "Archive=${archive}"
  restore_log "Target DB=${TARGET_DB}"
  restore_log "Format=${format}"
  restore_log "Encrypted=${RESTORE_META_ENCRYPTED}"
  restore_log "Dry-run=${RESTORE_DRY_RUN:-false}"
  restore_log "Extraction folder=${decrypt_folder}"

  ##########################################
  # DRY RUN — exit early
  ##########################################
  if is_dry_run; then
    restore_log "[DRY-RUN] Would recreate DB ${TARGET_DB}"
    restore_log "[DRY-RUN] Would restore archive ${archive}"
    restore_log "[DRY-RUN] Restore skipped"
    return 0
  fi



  create_non_existing_directory "${decrypt_folder}"

  ##########################################
  # Compatibility + checksum (once, transport)
  ##########################################
  check_pg_major_compatibility "${RESTORE_META_PG_MAJOR}" || return 1

  if [[ -n "${RESTORE_META_CHECKSUM}" ]]; then
    validate_checksum "${archive}" || return 1
  fi

  ##########################################
  # Recreate DB
  ##########################################
  restore_recreate_db "${TARGET_DB}" || return 1

  ##########################################
  # DIRECTORY FORMAT (-Fd → .tar.gz)
  ##########################################
  if [[ "${format}" == "directory" ]]; then
    [[ "${archive}" != *.tar.gz ]] && {
      restore_log "ERROR: Directory-format restore requires .tar.gz archive"
      return 1
    }

    local filename base_name
    filename="$(basename "${archive}")"
    base_name="${filename%.tar.gz}"

    restore_log "Extracting directory dump ${archive} into ${decrypt_folder}/${base_name}"
    tar -xzf "${archive}" -C "${decrypt_folder}" || {
      restore_log "ERROR: Failed to extract ${archive}"
      return 1
    }

    restore_dump "${decrypt_folder}/${base_name}" "${TARGET_DB}" || return 1

  ##########################################
  # CUSTOM FORMAT (-Fc → .dmp / .dmp.gz)
  ##########################################
  else
    local dump_file="${archive}"

    # Handle S3-style compressed custom dumps
    if [[ "${archive}" == *.gz ]]; then
      restore_log "Decompressing custom dump ${archive}"
      gunzip -kf "${archive}" || return 1
      dump_file="${archive%.gz}"
    fi



    restore_dump "${dump_file}" "${TARGET_DB}" "${RESTORE_META_ENCRYPTED}" || return 1
  fi

  restore_log "File restore completed successfully for ${TARGET_DB}"
  return 0
}

