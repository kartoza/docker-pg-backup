#!/usr/bin/env bash
set -Eeuo pipefail


############################################
# Helpers
############################################
db_log() {
  log "[DB] $*"
}

############################################
# Readiness check
############################################
check_db_ready() {
  db_log "Checking database readiness"
  PGPASSWORD="${POSTGRES_PASS}" \
    psql ${PG_CONN_PARAMETERS} -d postgres -c "SELECT 1" >/dev/null
}

############################################
# Globals backup
############################################
backup_globals() {
  db_log "Starting globals backup"

  set -o pipefail

  if [[ "${STORAGE_BACKEND}" == "S3" ]]; then
    db_log "Backing up globals.sql to S3 bucket ${BUCKET}"

    if PGPASSWORD="${POSTGRES_PASS}" \
      pg_dumpall ${PG_CONN_PARAMETERS} --globals-only \
      | s3cmd put - "s3://${BUCKET}/globals.sql"
    then
      db_log "Globals backup to S3 completed successfully"
    else
      db_log "ERROR: Globals backup to S3 failed"
      notify_monitoring "failure"
      exit 1
    fi

  else
    mkdir -p "${MYBASEDIR}"

    db_log "Backing up globals.sql to filesystem (${MYBASEDIR})"

    if PGPASSWORD="${POSTGRES_PASS}" \
      pg_dumpall ${PG_CONN_PARAMETERS} --globals-only \
      > "${MYBASEDIR}/globals.sql"
    then
      db_log "Globals backup to filesystem completed successfully"
    else
      db_log "ERROR: Globals backup to filesystem failed"
      notify_monitoring "failure"
      exit 1
    fi
  fi

  set +o pipefail
}
############################################
# Main DB backup dispatcher
############################################
backup_databases() {
  local post_hook="${1:-}"

  for DB in ${DBLIST}; do
    backup_single_database "${DB}" "${post_hook}"

    if [[ "${DB_TABLES,,}" =~ [Tt][Rr][Uu][Ee] ]]; then
      dump_tables "${DB}"
    fi
  done
}

############################################
# Single DB backup
############################################
backup_single_database() {
  local DB="$1"
  local post_hook="$2"

  mkdir -p "${MYBACKUPDIR}"

  if [ -z "${ARCHIVE_FILENAME:-}" ]; then
      BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}"

    else
      BASE_FILENAME="${MYBASEDIR}/${ARCHIVE_FILENAME}.${DB}"

  fi
  local filename="${BASE_FILENAME}.dmp"



  export PGPASSWORD="${POSTGRES_PASS}"

  if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    db_log "Starting encrypted backup of database ${DB}"
    require_encryption_key

    set -o pipefail
    pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" \
      | encrypt_stream \
      > "${filename}"
    if [[ "${CHECKSUM_VALIDATION}" =~ [Tt][Rr][Uu][Ee] ]];then
      sha256sum "${filename}" > "${filename}.sha256"
    fi
    db_log "Encrypted Backup successful for ${DB}"
    set +o pipefail
  else
    db_log "Starting backup of database ${DB}"
    pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" \
      > "${filename}"
    if [[ "${CHECKSUM_VALIDATION}" =~ [Tt][Rr][Uu][Ee] ]];then
      sha256sum "${filename}" > "${filename}.sha256"
    fi
    db_log "Backup successful for ${DB}"
  fi



  ##########################################
  # Optional post-processing (S3)
  ##########################################
  if [[ "${STORAGE_BACKEND}" == "S3" ]]; then
    gzip -c -f "${filename}" > "${BASE_FILENAME}.dmp.gz"

    if [[ "${CHECKSUM_VALIDATION}" =~ [Tt][Rr][Uu][Ee] ]];then
      sha256sum "${BASE_FILENAME}.dmp.gz" > "${BASE_FILENAME}.dmp.gz.sha256"
    fi
    s3_upload "${BASE_FILENAME}.dmp.gz"

    cleanup_file "${filename}"
    cleanup_file "${BASE_FILENAME}.dmp.gz.sha256"

    if [[ -n "${post_hook}" ]]; then
      "${post_hook}" "${BASE_FILENAME}.dmp.gz"
    fi
fi
}

############################################
# Table-level dumps
############################################
dump_tables() {
  local DATABASE="$1"

  db_log "Starting table-level dumps for ${DATABASE}"

  mapfile -t tables < <(
    PGPASSWORD="${POSTGRES_PASS}" \
    psql ${PG_CONN_PARAMETERS} -d "${DATABASE}" -At -F '.' \
    -c "SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_schema NOT IN ('information_schema','pg_catalog','topology')
        ORDER BY table_schema, table_name"
  )

  for tbl in "${tables[@]}"; do
    local schema="${tbl%%.*}"
    local table="${tbl##*.}"
    local fqtn="${schema}.${table}"
    local out="${MYBACKUPDIR}/${DUMPPREFIX}_${fqtn}_${MYDATE}.sql"



    if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      set -o pipefail
      db_log "Dumping Encrypted table ${fqtn}"
      pg_dump ${PG_CONN_PARAMETERS} -d "${DATABASE}" -t "${fqtn}" \
        | encrypt_stream \
        > "${out}"
      set +o pipefail
    else
      db_log "Dumping table ${fqtn}"
      pg_dump ${PG_CONN_PARAMETERS} -d "${DATABASE}" -t "${fqtn}" \
        > "${out}"
    fi
  done
}

############################################
# Drop & recreate DB
############################################
restore_recreate_db() {
  local db="$1"

  db_log "Recreating database ${db}"

  export PGPASSWORD="${POSTGRES_PASS}"

  dropdb ${PG_CONN_PARAMETERS} --if-exists --force "${db}"
  createdb ${PG_CONN_PARAMETERS} -O "${POSTGRES_USER}" "${db}"

  if [[ -n "${WITH_POSTGIS:-}" ]]; then
    db_log "Enabling PostGIS"
    psql ${PG_CONN_PARAMETERS} -d "${db}" -c 'CREATE EXTENSION IF NOT EXISTS postgis;'
  fi
}

############################################
# Restore dump (encrypted or not)
############################################
restore_dump() {
  local archive="$1"
  local db="$2"

  export PGPASSWORD="${POSTGRES_PASS}"

  if [[ "${DB_DUMP_ENCRYPTION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    db_log "Restoring encrypted dump into ${db}"
    openssl enc -d -aes-256-cbc \
      -pass pass:"${DB_DUMP_ENCRYPTION_PASS_PHRASE}" \
      -pbkdf2 -iter 10000 -md sha256 \
      -in "${archive}" \
      -out /tmp/decrypted.dump

    pg_restore ${PG_CONN_PARAMETERS} /tmp/decrypted.dump -d "${db}" ${RESTORE_ARGS}
    rm -f /tmp/decrypted.dump
  else
    db_log "Restoring dump into ${db}"
    pg_restore ${PG_CONN_PARAMETERS} "${archive}" -d "${db}" ${RESTORE_ARGS}
  fi
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
    db_log "ERROR: validate_checksum called without archive"
    return 1
  }

  [[ ! -f "${archive}" ]] && {
    db_log "ERROR: Archive not found: ${archive}"
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
    db_log "ERROR: Checksum file missing: ${checksum_file}"
    return 1
  }

  db_log "Validating checksum for $(basename "${archive}")"

  sha256sum -c "${checksum_file}" >/dev/null 2>&1 || {
    db_log "ERROR: Checksum validation FAILED for $(basename "${archive}")"
    return 1
  }

  db_log "Checksum validation PASSED for $(basename "${archive}")"
  return 0
}

cleanup_file() {
  local file="$1"

  if [[ -f "${file}"  ]]; then
    rm -rf "${file}"
    db_log "Deleting file ${file}"
  fi
}

normalize_archive() {
  local path="$1"

  [[ -z "${path:-}" ]] && {
    db_log "ERROR: normalize_archive called without argument"
    return 1
  }

  # Equivalent to Python os.path.basename()
  echo "${path##*/}"
}