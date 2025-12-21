#!/usr/bin/env bash

set -e

# execute tests
pushd /tests
# Get env variables
source /backup-scripts/pgenv.sh

PGHOST=localhost \
PGDATABASE=gis \
PYTHONPATH=/lib \
  python3 -m unittest -v test_file_retentions.TestRetentionFile



