#!/usr/bin/env bash
set -euo pipefail


export MONITORING_OUTPUT_FILE="/tmp/monitoring_status.txt"

rm -f "${MONITORING_OUTPUT_FILE}"

########################################
# Run the real backup script
########################################
"/backup-scripts/backups.sh" || true

########################################
# Validate monitoring result
########################################
if [[ ! -f "${MONITORING_OUTPUT_FILE}" ]]; then
  echo "monitoring was not triggered"
  exit 1
fi

STATUS="$(cat "${MONITORING_OUTPUT_FILE}")"

echo "Monitoring reported: ${STATUS}"

if [[ "${STATUS}" != "SUCCESS" && "${STATUS}" != "FAILURE" ]]; then
  echo "invalid monitoring status"
  exit 1
fi

echo "monitoring integration test passed"