#!/usr/bin/env bash

encrypt_dump() {
  local db="$1"
  local outfile="$2"

  local passfile
  passfile="$(mktemp)"
  chmod 600 "${passfile}"
  echo "${DB_DUMP_ENCRYPTION_PASS_PHRASE}" > "${passfile}"

  pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${db}" \
    | openssl enc -aes-256-cbc \
        -pbkdf2 -iter 10000 -md sha256 \
        -pass file:"${passfile}" \
        -out "${outfile}"

  rm -f "${passfile}"
}