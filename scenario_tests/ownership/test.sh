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

################################################
# Perform DB backup and restore using gosu
#################################################
${VERSION} up -d

sleep 120

# Backup DB
${VERSION} exec pg_restore  /backup-scripts/backups.sh

# Restore DB backup
${VERSION} exec pg_restore  /backup-scripts/restore.sh

# Execute tests
${VERSION} exec pg_restore /bin/bash /tests/test_restore.sh


${VERSION} down -v



