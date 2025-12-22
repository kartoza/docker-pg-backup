#!/usr/bin/env bash
set -Eeuo pipefail


############################################
# Helpers
############################################
utils_log() {
  log "[DB Utils] $*"
}


############################################
# Checksum validation helper
# Usage: validate_checksum <archive_file>
############################################
validate_checksum() {
  local archive="$1"

  # Skip entirely if checksum validation disabled
  [[ "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]] || return 0

  [[ -z "${archive:-}" ]] && {
    utils_log "ERROR: validate_checksum called without archive"
    return 1
  }

  [[ ! -f "${archive}" ]] && {
    utils_log "ERROR: Archive not found: ${archive}"
    return 1
  }

  local checksum_file

  # If caller passed .sha256 explicitly, use it
  if [[ "${archive}" == *.sha256 ]]; then
    checksum_file="${archive}"
  else
    checksum_file="${archive}.sha256"
  fi

  [[ ! -f "${checksum_file}" ]] && {
    utils_log "ERROR: Checksum file missing: ${checksum_file}"
    return 1
  }

  utils_log "Validating checksum for $(basename "${archive}")"

    (
    cd "$(dirname "${archive}")" || return 1
    sha256sum -c "$(basename "${checksum_file}")" >/dev/null 2>&1
  ) || {
    utils_log "ERROR: Checksum validation FAILED for $(basename "${archive}")"
    return 1
  }

  utils_log "Checksum validation PASSED for $(basename "${archive}")"
  return 0
}

############################################
# Cleanup file helper
# Usage: cleanup_file <archive_file>
############################################

cleanup_file() {
  local file="$1"

  if [[ -f "${file}"  ]]; then
    rm -rf "${file}"
    utils_log "Deleting file ${file}"
  fi
}

############################################
# Normalize Archive helper
# Usage: normalize_archive <path>
############################################

normalize_archive() {
  local path="$1"

  [[ -z "${path:-}" ]] && {
    utils_log "ERROR: normalize_archive called without argument"
    return 1
  }

  # Equivalent to Python os.path.basename()
  echo "${path##*/}"
}

############################################
# Generate Checksum file helper
# Usage: generate_gz_checksum <archive_file>
############################################

generate_gz_checksum() {
  local gz_file="$1"

  [[ ! -f "${gz_file}" ]] && {
    utils_log "ERROR: Cannot checksum missing file ${gz_file}"
    return 1
  }

  (
    cd "$(dirname "${gz_file}")" || return 1
    sha256sum "$(basename "${gz_file}")" > "$(basename "${gz_file}").sha256"
  )
}

############################################
# Cleanups Backups helper
# Usage: cleanup_backup <archive_file>
############################################

cleanup_backup() {
  local gz_file="$1"
  if [[ -f "${gz_file}"  ]]; then
    rm -rf "${gz_file}"
    utils_log "Deleting file ${gz_file}"
  fi
}

############################################
# Retry Logic Helper
# Usage: retry
############################################

retry() {
  local attempts="$1"
  shift
  local delay=2
  local n=1

  until "$@"; do
    if (( n >= attempts )); then
      return 1
    fi
    sleep $(( delay * n ))
    ((n++))
  done
}


get_dump_format() {
  local DUMP_ARGS="$1"
  local FORMAT

  if [[ "${DUMP_ARGS}" =~ (^|[[:space:]])-Fd($|[[:space:]]) ]]; then
    FORMAT="directory"
  elif [[ "${DUMP_ARGS}" =~ (^|[[:space:]])-Fc($|[[:space:]]) ]]; then
    FORMAT="custom"
  else
    FORMAT="other"
  fi


   echo "${FORMAT}"
}

extract_ts_from_filename() {
  local fname="$1"
  local raw datestr ts

  raw=$(sed -n 's/.*\.\([0-9]\{2\}-[A-Za-z]\+-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\..*/\1/p' <<< "$fname")

  [[ -z "$raw" ]] && { echo 0; return; }

  # Convert: DD-Month-YYYY-HH-MM → "DD Month YYYY HH:MM"
  datestr="$(sed 's/-/ /1; s/-/ /1; s/-/ /1; s/-/:/' <<< "$raw")"

  ts=$(date -d "$datestr" +%s 2>/dev/null || echo 0)
  echo "$ts"
}