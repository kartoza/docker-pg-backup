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


########################################################
# Run tests using TARGET_ARCHIVE=/backups/latest.gis.dmp
########################################################

${VERSION} up -d

${VERSION} exec pg_restore  /backup-scripts/backups.sh

${VERSION} exec pg_restore  /backup-scripts/restore.sh

# Execute tests
${VERSION} exec pg_restore /bin/bash /tests/test_restore.sh


${VERSION} down -v

########################################################
# Run tests using TARGET_ARCHIVE=/backups/latest.gis.dmp
# Run with encryption
########################################################


${VERSION} -f docker-compose-encryption.yml up -d

# Backup DB
${VERSION} -f docker-compose-encryption.yml exec pg_restore  /backup-scripts/backups.sh

# Restore DB backup
${VERSION} -f docker-compose-encryption.yml exec pg_restore  /backup-scripts/restore.sh

# Execute tests
${VERSION} -f docker-compose-encryption.yml exec pg_restore /bin/bash /tests/test_restore.sh


${VERSION} -f docker-compose-encryption.yml down -v


##############################################################
# Run tests using TARGET_ARCHIVE=/backups/latest.gis.dir.tar.gz
# Run with directory backup
###############################################################

${VERSION} -f docker-compose-directory.yml up -d

# Backup DB
${VERSION} -f docker-compose-directory.yml exec pg_restore  /backup-scripts/backups.sh

# Restore DB backup
${VERSION} -f docker-compose-directory.yml exec pg_restore  /backup-scripts/restore.sh

# Execute tests
${VERSION} -f docker-compose-directory.yml exec pg_restore /bin/bash /tests/test_restore.sh


${VERSION} -f docker-compose-directory.yml down -v