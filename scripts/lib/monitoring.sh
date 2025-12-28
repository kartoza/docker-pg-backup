#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Helpers
############################################
monitoring_log() {
  log "[DB Monitoring] $*"
}

notify_monitoring() {
  local status="${1:-unknown}"

  monitoring_log "notify_monitoring called with status=${status}"

  # Command-based monitoring
  if [[ -n "${MONITORING_ENDPOINT_COMMAND:-}" ]]; then
    monitoring_log "notify_monitoring: running MONITORING_ENDPOINT_COMMAND ${MONITORING_ENDPOINT_COMMAND} and status ${status}"
    eval "${MONITORING_ENDPOINT_COMMAND} '${status}'"
    return 0
  fi

  # Script-based monitoring
  if [[ -n "${EXTRA_CONF_DIR:-}" ]] && \
     [[ -f "${EXTRA_CONF_DIR}/backup_monitoring.sh" ]]; then
    monitoring_log "notify_monitoring: running ${EXTRA_CONF_DIR}/backup_monitoring.sh ${status}"
    bash "${EXTRA_CONF_DIR}/backup_monitoring.sh" "${status}"
    return 0
  fi

  # Safe fallback
  monitoring_log "notify_monitoring: no monitoring configured"
  return 0
}