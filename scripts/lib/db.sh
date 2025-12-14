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
backup_globals_file() {
  mkdir -p "${MYBACKUPDIR}"
  db_log "Backing up globals.sql to filesystem"
  PGPASSWORD="${POSTGRES_PASS}" \
    pg_dumpall ${PG_CONN_PARAMETERS} --globals-only \
    > "${MYBACKUPDIR}/globals.sql"
}

backup_globals_s3() {
  db_log "Backing up globals.sql to S3"
  PGPASSWORD="${POSTGRES_PASS}" \
    pg_dumpall ${PG_CONN_PARAMETERS} --globals-only \
    | s3cmd put - "s3://${BUCKET}/globals.sql"
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

  local filename="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp"

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