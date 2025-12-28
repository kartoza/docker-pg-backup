#!/usr/bin/env bash
set -e

STATUS="${1:-unknown}"
OUT_FILE="${MONITORING_OUTPUT_FILE:-/tmp/monitoring_status.txt}"

# simulate something external (alerting system, webhook, etc.)
sleep 1

if [[ "$STATUS" == "success" ]]; then
  echo "SUCCESS" > "${OUT_FILE}"
  echo "Monitoring test  ran successfully"
  exit 0
else
  echo "FAILURE" > "${OUT_FILE}"
  echo "Monitoring test did not run successfully"
  exit 1
fi