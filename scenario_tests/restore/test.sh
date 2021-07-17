#!/usr/bin/env bash

# exit immediately if test fails
set -e

source ../test-env.sh

# Run service
docker-compose up -d

sleep 120

# Backup DB
docker-compose exec pg_restore  /backup-scripts/backups.sh

# Restore DB backup
docker-compose exec pg_restore  /backup-scripts/restore.sh

# Execute tests
docker-compose exec pg_restore /bin/bash /tests/test_restore.sh


docker-compose down -v
