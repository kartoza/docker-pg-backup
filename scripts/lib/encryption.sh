#!/usr/bin/env bash

require_encryption_key() {
  # Only required when encryption is enabled
  if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee]|1)$ ]]; then
    if [[ -z "${DB_DUMP_ENCRYPTION_PASS_PHRASE:-}" ]]; then
      log "ERROR: DB_DUMP_ENCRYPTION is enabled but DB_DUMP_ENCRYPTION_PASS_PHRASE is not set"
      notify_monitoring "failure"
      exit 1
    fi
  fi
}

encrypt_stream() {
  # stdin → stdout
  require_encryption_key

  openssl enc -aes-256-cbc \
    -pbkdf2 -iter 10000 -md sha256 \
    -pass "pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE}"
}

decrypt_stream() {
  # stdin → stdout
  require_encryption_key

  openssl enc -d -aes-256-cbc \
    -pbkdf2 -iter 10000 -md sha256 \
    -pass "pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE}"
}

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