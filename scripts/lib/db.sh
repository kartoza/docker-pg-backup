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

    db_log "Backing up globals.sql to filesystem (${MYBACKUPDIR})"

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
      local filename="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp"
    else
      local filename="${MYBASEDIR}/${ARCHIVE_FILENAME}.${DB}.dmp"
  fi

  db_log "Starting backup of database ${DB}"

  export PGPASSWORD="${POSTGRES_PASS}"

  if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    require_encryption_key

    set -o pipefail
    pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" \
      | encrypt_stream \
      > "${filename}"
    set +o pipefail
  else
    pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" \
      > "${filename}"
  fi

  db_log "Backup successful for ${DB}"

  ##########################################
  # Optional post-processing (S3)
  ##########################################
  if [[ "${STORAGE_BACKEND}" == "S3" ]]; then
    gzip -f "${filename}"

    if [[ -n "${post_hook}" ]]; then
      "${post_hook}" "${filename}.gz"
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

    db_log "Dumping table ${fqtn}"

    if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      set -o pipefail
      pg_dump ${PG_CONN_PARAMETERS} -d "${DATABASE}" -t "${fqtn}" \
        | encrypt_stream \
        > "${out}"
      set +o pipefail
    else
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

  db_log "Restoring dump into ${db}"

  export PGPASSWORD="${POSTGRES_PASS}"

  if [[ "${DB_DUMP_ENCRYPTION}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    openssl enc -d -aes-256-cbc \
      -pass pass:"${DB_DUMP_ENCRYPTION_PASS_PHRASE}" \
      -pbkdf2 -iter 10000 -md sha256 \
      -in "${archive}" \
      -out /tmp/decrypted.dump

    pg_restore ${PG_CONN_PARAMETERS} /tmp/decrypted.dump -d "${db}" ${RESTORE_ARGS}
    rm -f /tmp/decrypted.dump
  else
    pg_restore ${PG_CONN_PARAMETERS} "${archive}" -d "${db}" ${RESTORE_ARGS}
  fi
}