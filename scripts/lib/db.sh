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
  local max_wait="${DB_READY_TIMEOUT:-20}"
  local interval=2
  local elapsed=0

  db_log "Checking database readiness (timeout=${max_wait}s)"

  while true; do
    if PGPASSWORD="${POSTGRES_PASS}" \
       psql ${PG_CONN_PARAMETERS} -d postgres -c "SELECT 1" >/dev/null 2>&1; then
      db_log "Database is ready"
      return 0
    fi

    if (( elapsed >= max_wait )); then
      db_log "ERROR: Database not ready after ${max_wait}s"
      return 1
    fi

    sleep "${interval}"
    elapsed=$(( elapsed + interval ))
  done
}

############################################
# Globals backup
############################################
backup_globals() {
  db_log "Starting globals backup at $(date +%d-%B-%Y-%H-%M)"

  set -o pipefail

  if [[ "${STORAGE_BACKEND}" == "S3" ]]; then
    db_log "Backing up globals.sql to S3 bucket ${BUCKET}"

    if PGPASSWORD="${POSTGRES_PASS}" \
      pg_dumpall ${PG_CONN_PARAMETERS} --globals-only \
      | s3cmd put - "s3://${BUCKET}/globals.sql"
    then
      db_log "Globals backup to S3 completed successfully at $(date +%d-%B-%Y-%H-%M)"
    else
      db_log "ERROR: Globals backup to S3 failed at $(date +%d-%B-%Y-%H-%M)"
      notify_monitoring "failure"
      exit 1
    fi

  else


    db_log "Backing up globals.sql to filesystem (${MYBASEDIR})"

    if PGPASSWORD="${POSTGRES_PASS}" \
      pg_dumpall ${PG_CONN_PARAMETERS} --globals-only \
      > "${MYBASEDIR}/globals.sql"
    then
      db_log "Globals backup to filesystem completed successfully at $(date +%d-%B-%Y-%H-%M)"
    else
      db_log "ERROR: Globals backup to filesystem failed at $(date +%d-%B-%Y-%H-%M)"
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
  local status="success"

  mkdir -p "${MYBACKUPDIR}"

  if [[ -z "${ARCHIVE_FILENAME:-}" ]]; then
    BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}"
  else
    BASE_FILENAME="${MYBASEDIR}/${ARCHIVE_FILENAME}.${DB}"
  fi

  export PGPASSWORD="${POSTGRES_PASS}"

  ##########################################
  # Detect dump format
  ##########################################
  FORMAT="$(get_dump_format "${DUMP_ARGS}")"

  db_log "Starting backup of database ${DB} using format ${FORMAT} at $(date +%d-%B-%Y-%H-%M)"

  ##########################################
  # Perform dump
  ##########################################
  if [[ "${FORMAT}" == "directory" ]]; then
    local dump_dir="${BASE_FILENAME}.dir"
    local tar_file="${BASE_FILENAME}.dir.tar.gz"

    rm -rf "${dump_dir}"
    mkdir -p "${dump_dir}"

    if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      db_log "ERROR: Encryption not supported with directory format"
      status="failure"
    fi

    if [[ "${status}" == "success" && -d "${dump_dir}" ]]; then
      pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" -f "${dump_dir}" \
        || status="failure"

      if [[ "${status}" == "success" ]]; then
        db_log "Tarring directory dump with max compression"
        tar -C "$(dirname "${dump_dir}")" \
            -I 'gzip -9' \
            -cf "${tar_file}" "$(basename "${dump_dir}")" \
            || status="failure"
      fi

      rm -rf "${dump_dir}"
    else
      db_log "Missing dump directory ${dump_dir}"
      status="failure"
    fi

    if [[ "${status}" == "success" && "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      generate_gz_checksum "${tar_file}" || status="failure"
    fi

    if [[ "${status}" == "success" && "${STORAGE_BACKEND}" == "S3" ]]; then
      s3_upload "${tar_file}" || status="failure"
      if [[ "${S3_RETAIN_LOCAL_DUMPS:-false}" =~ ^([Ff][Aa][Ll][Ss][Ee])$ ]];then
        cleanup_file "${tar_file}.sha256"
      fi
    fi

    [[ "${status}" == "success" && -n "${post_hook}" ]] && "${post_hook}" "${tar_file}"

  else
    local dump_file="${BASE_FILENAME}.dmp"
    local gz_file="${BASE_FILENAME}.dmp.gz"

    if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      require_encryption_key
      set -o pipefail
      pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" \
        | encrypt_stream > "${dump_file}"
      rc=$?
      set +o pipefail
      [[ $rc -ne 0 ]] && status="failure"
    else
      pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" > "${dump_file}" \
        || status="failure"
    fi

    if [[ "${status}" == "success" && "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      generate_gz_checksum "${dump_file}" || status="failure"
    fi

    if [[ "${status}" == "success" && "${STORAGE_BACKEND}" == "S3" ]]; then
      gzip -9 -c "${dump_file}" > "${gz_file}" || status="failure"
      if [[ "${S3_RETAIN_LOCAL_DUMPS:-false}" =~ ^([Ff][Aa][Ll][Ss][Ee])$ ]];then
        cleanup_file "${dump_file}"
      fi

      if [[ "${status}" == "success" && "${CHECKSUM_VALIDATION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
        generate_gz_checksum "${gz_file}" || status="failure"
      fi

      s3_upload "${gz_file}" || status="failure"
      if [[ "${S3_RETAIN_LOCAL_DUMPS:-false}" =~ ^([Ff][Aa][Ll][Ss][Ee])$ ]];then
        cleanup_file "${gz_file}.sha256"
      fi
    fi

    [[ "${status}" == "success" && -n "${post_hook}" ]] && "${post_hook}" "${gz_file}"
  fi

  ##########################################
  # Final status + monitoring
  ##########################################
  if [[ "${status}" == "success" ]]; then
    db_log "Backup completed for ${DB} at $(date +%d-%B-%Y-%H-%M)"
  else
    db_log "Backup FAILED for ${DB} at $(date +%d-%B-%Y-%H-%M)"
  fi

  notify_monitoring "${status}" || true
  [[ "${status}" == "success" ]]
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
        WHERE table_schema NOT IN ('information_schema','pg_catalog','topology', 'pg_toast')
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
  FORMAT="$(get_dump_format "${DUMP_ARGS}")"
  if [[ "${FORMAT}" == "directory" ]]; then
    db_log "Restoring directory dump into ${db}"
    pg_restore ${PG_CONN_PARAMETERS} "${archive}" -d "${db}" ${RESTORE_ARGS}

  else

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
  fi
}

