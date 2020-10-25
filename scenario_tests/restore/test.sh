#!/usr/bin/env bash

# exit immediately if test fails
set -e

source ../test-env.sh

# Run service
docker-compose up -d

sleep 120

# Restore DB backup
docker-compose exec pg_restore  /backup-scripts/backups.sh

# Preparing pg_restore cluster
until docker-compose exec pg_restore pg_isready; do
  sleep 10
done;

# Restore DB backup
docker-compose exec pg_restore  /backup-scripts/restore.sh

# Execute tests
docker-compose exec pg_restore /bin/bash /tests/test_restore.sh


docker-compose down -v
