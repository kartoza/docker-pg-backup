#!/usr/bin/env bash
set -Eeuo pipefail

init_logging() {
  if [[ "${CONSOLE_LOGGING:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    LOG_MODE="stdout"
  else
    LOG_MODE="file"
    LOG_FILE="/var/log/cron.out"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
  fi

  export LOG_MODE LOG_FILE
}

log() {
  local msg="[$(date --iso-8601=seconds)] $*"

  if [[ "${LOG_MODE}" == "stdout" ]]; then
    echo "${msg}"
  else
    echo "${msg}" >> "${LOG_FILE}"
  fi
}

on_error() {
  local line="$1"
  log "ERROR at line ${line}"
  notify_monitoring "failure"
  exit 2
}

on_terminate() {
  log "Termination signal received"
  exit 143
}