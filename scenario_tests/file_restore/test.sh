#!/usr/bin/env bash

# exit immediately if test fails
set -e

source ../test-env.sh

# Determine docker compose version to use
if [[ $(dpkg -l | grep "docker-compose") > /dev/null ]];then
    VERSION='docker-compose'
  else
    VERSION='docker compose'
fi

run_tests() {
  local docker_cmd="$1"
  local compose_file="$2"

  local compose_args=()

  # Only add -f if NOT default compose file
  if [[ "${compose_file}" != "docker-compose.yml" ]]; then
    compose_args=(-f "${compose_file}")
  fi

  echo "Starting services using ${compose_file}"
  ${docker_cmd}  "${compose_args[@]}" up -d

  echo "Running backup for compose: ${compose_file}"
  ${docker_cmd}  "${compose_args[@]}" exec pg_restore /backup-scripts/backups.sh

  if [[ ${compose_file} == 'docker-compose-date.yml' || ${compose_file} == 'docker-compose-date-time.yml' ]];then
    echo "Extracting Date and Datetime Vars for Restore script for: ${compose_file}"
    ${docker_cmd}  "${compose_args[@]}" exec pg_restore /bin/bash /tests/date_vars.sh
  fi

  echo "Running restore for compose: ${compose_file}"
  ${docker_cmd}  "${compose_args[@]}" exec pg_restore /backup-scripts/restore.sh

  echo "Running unit tests for compose: ${compose_file}"
  ${docker_cmd}  "${compose_args[@]}" exec pg_restore /bin/bash /tests/test_restore.sh

  echo "Bringing down services for compose: ${compose_file}"
  ${docker_cmd}  "${compose_args[@]}" down -v
}

compose_names=("docker-compose.yml" "docker-compose-encryption.yml" "docker-compose-directory.yml" "docker-compose-date-time.yml" "docker-compose-date.yml")
for compose_file in "${compose_names[@]}"; do

  run_tests "${VERSION}" "${compose_file}"
done



