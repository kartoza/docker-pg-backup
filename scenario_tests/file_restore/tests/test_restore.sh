#!/usr/bin/env bash

set -e

source /backup-scripts/pgenv.sh

# execute tests
pushd /tests

PGHOST=localhost \
PGDATABASE=${TARGET_DB} \
PYTHONPATH=/lib \
  python3 -m unittest -v test_restore.TestRestore
