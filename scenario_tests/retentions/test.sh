#!/usr/bin/env bash

# exit immediately if test fails
set -e

source ../test-env.sh

# Run service
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

  if [[ "${compose_file}" == "docker-compose.yml" ]]; then
    echo "Generating Mock backups data for compose: ${compose_file}"
    ${docker_cmd}  "${compose_args[@]}" exec pg_restore /tests/old_backups.sh

    echo "Running unit tests for compose: ${compose_file}"
    ${docker_cmd}  "${compose_args[@]}" exec pg_restore /bin/bash /tests/test_retension_file.sh
  else
    echo "Running unit tests for compose: ${compose_file}"
    ${docker_cmd}  "${compose_args[@]}" exec pg_restore /bin/bash /tests/test_retension_s3.sh
  fi

  echo "Bringing down services for compose: ${compose_file}"
  ${docker_cmd}  "${compose_args[@]}" down -v
}

compose_names=("docker-compose.yml" "docker-compose-s3.yml")
for compose_file in "${compose_names[@]}"; do
  run_tests "${VERSION}" "${compose_file}"
done



