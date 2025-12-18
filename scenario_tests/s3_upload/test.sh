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
# Perform DB backup to s3 endpoint using
# directory structure i.e 2025/June/PG_gis.dmp.gz
#################################################
${VERSION} up -d

sleep 30

${VERSION} exec pg_restore  /backup-scripts/backups.sh

# Execute tests
${VERSION} exec pg_restore /bin/bash /tests/test_upload.sh


${VERSION} down -v

################################################
# Perform DB backup to s3 endpoint using
# ARCHIVE_FILENAME=latest
#################################################
${VERSION} -f docker-compose-latest.yml up -d

sleep 30

${VERSION} -f docker-compose-latest.yml exec pg_restore  /backup-scripts/backups.sh

# Execute tests
${VERSION} -f docker-compose-latest.yml exec pg_restore /bin/bash /tests/test_upload.sh


${VERSION} -f docker-compose-latest.yml down -v
################################################
# Perform DB backup to s3 endpoint using
# directory structure i.e 2025/June/PG_gis.dmp.gz
# Also check if checksum is uploaded correctly
#################################################

sed -i 's/CHECKSUM_VALIDATION=False/CHECKSUM_VALIDATION=True/' docker-compose.yml

${VERSION} up -d

sleep 30
# Perform DB backup to s3 endpoint this time with checksum
${VERSION} exec pg_restore  /backup-scripts/backups.sh

# Execute tests
${VERSION} exec pg_restore /bin/bash /tests/test_upload.sh


${VERSION} down -v
sed -i 's/CHECKSUM_VALIDATION=True/CHECKSUM_VALIDATION=False/' docker-compose.yml
