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
  local msg
  local colorize


  if [[ "$#" -ge 2 && "${!#}" =~ ^([Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee])$ ]]; then
    colorize="${!#}"
    set -- "${@:1:$(($#-1))}"
  else
    colorize="${COLORIZE:-false}"
  fi

 local ts
  ts="$(date --iso-8601=seconds)"
  msg="[$(date --iso-8601=seconds)] $*"

  if [[ "${LOG_MODE}" == "stdout" ]]; then
    if [[ "${JSON_LOGGING}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
      printf '{"ts":"%s","msg":"%s"}\n' \
        "$ts" \
        "$(printf '%s' "$*" | sed 's/"/\\"/g')"
    else
      if [[ "${colorize}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
        echo -e "\e[32m${msg}\033[0m"
      else
        echo "${msg}"
      fi
    fi
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