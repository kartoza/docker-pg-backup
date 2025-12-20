#!/usr/bin/env bash
set -Eeuo pipefail

notify_monitoring() {
  local status="${1:-unknown}"

  # Command-based monitoring
  if [[ -n "${MONITORING_ENDPOINT_COMMAND:-}" ]]; then
    eval "${MONITORING_ENDPOINT_COMMAND}"
    return 0
  fi

  # Script-based monitoring
  if [[ -n "${EXTRA_CONFIG_DIR:-}" ]] && \
     [[ -f "${EXTRA_CONFIG_DIR}/backup_monitoring.sh" ]]; then
    bash "${EXTRA_CONFIG_DIR}/backup_monitoring.sh" "${status}"
    return 0
  fi

  # Safe fallback
  return 0
}