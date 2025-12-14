#!/usr/bin/env bash

init_env() {
  : "${POSTGRES_HOST:=db}"
  : "${POSTGRES_PORT:=5432}"
  : "${POSTGRES_USER:=docker}"
  : "${POSTGRES_PASS:=docker}"
  : "${STORAGE_BACKEND:=FILE}"
  : "${DBLIST:=}"
  : "${REMOVE_BEFORE:=}"
  : "${MIN_SAVED_FILE:=0}"
  : "${CONSOLIDATE_AFTER:=0}"
  : "${DB_DUMP_ENCRYPTION:=false}"
  : "${ENABLE_S3_BACKUP:=false}"
  : "${CLEANUP_DRY_RUN:=false}"

  export PGPASSWORD="${POSTGRES_PASS}"
  export PG_CONN_PARAMETERS="-h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER}"

  MYDATE="$(date +%d-%B-%Y-%H-%M)"
  MONTH="$(date +%B)"
  YEAR="$(date +%Y)"

  MYBASEDIR="/${BUCKET:-backups}"
  MYBACKUPDIR="${MYBASEDIR}/${YEAR}/${MONTH}"
  mkdir -p "${MYBACKUPDIR}"
}