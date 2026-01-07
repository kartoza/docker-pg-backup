#!/usr/bin/env bash

require_encryption_key() {
  if [[ "${DB_DUMP_ENCRYPTION:-false}" =~ ^([Tt][Rr][Uu][Ee]|1)$ ]]; then
    validate_dump_encryption_pass

    if [[ -z "${DB_DUMP_ENCRYPTION_PASS_PHRASE:-}" ]]; then
      log "ERROR: DB_DUMP_ENCRYPTION is enabled but encryption passphrase is missing"
      notify_monitoring "failure"
      exit 1
    fi
  fi
}

encrypt_stream() {
  require_encryption_key

  openssl enc -aes-256-cbc \
    -pbkdf2 -iter 10000 -md sha256 \
    -pass "pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE}"
}

decrypt_stream() {
  require_encryption_key

  openssl enc -d -aes-256-cbc \
    -pbkdf2 -iter 10000 -md sha256 \
    -pass "pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE}"
}

encrypt_dump() {
  local db="$1"
  local outfile="$2"

  require_encryption_key

  local passfile
  passfile="$(mktemp)"
  chmod 600 "${passfile}"
  printf '%s' "${DB_DUMP_ENCRYPTION_PASS_PHRASE}" > "${passfile}"

  pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${db}" \
    | openssl enc -aes-256-cbc \
        -pbkdf2 -iter 10000 -md sha256 \
        -pass file:"${passfile}" \
        -out "${outfile}"

  rm -f "${passfile}"
}