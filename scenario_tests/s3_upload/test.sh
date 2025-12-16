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
${VERSION} up -d

sleep 30

# Perform DB backup to s3 endpoint
${VERSION} exec pg_restore  /backup-scripts/backups.sh

# Execute tests
${VERSION} exec pg_restore /bin/bash /tests/test_upload.sh


${VERSION} down -v

# Update the docker compose and check if

sed -i 's/CHECKSUM_VALIDATION=False/CHECKSUM_VALIDATION=True/' docker-compose.yml
# Perform DB backup to s3 endpoint this time with checksum
${VERSION} exec pg_restore  /backup-scripts/backups.sh

# Execute tests
${VERSION} exec pg_restore /bin/bash /tests/test_upload.sh


${VERSION} down -v
sed -i 's/CHECKSUM_VALIDATION=True/CHECKSUM_VALIDATION=False/' docker-compose.yml
