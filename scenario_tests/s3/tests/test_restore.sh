#!/usr/bin/env bash

set -e

/backup-scripts/pgenv.sh
# execute tests
pushd /tests

PGHOST=localhost \
PGDATABASE=gis \
PYTHONPATH=/lib \
  python3 -m unittest -v test_restore.TestRestore


# Clean up artifact
s3cmd rm --force --recursive s3://${BUCKET}
