#!/usr/bin/env bash

# exit immediately if test fails
set -e

source ../test-env.sh

# Run service
docker-compose up -d

sleep 120

# Perform DB backup to s3 endpoint
docker-compose exec pg_restore  /backup-scripts/backups.sh

# Execute tests
docker-compose exec pg_restore /bin/bash /tests/test_restore.sh


docker-compose down -v
