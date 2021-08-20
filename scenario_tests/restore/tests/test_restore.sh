#!/usr/bin/env bash

set -e

source /scripts/env-data.sh

# execute tests
pushd /tests

PGHOST=localhost \
PGDATABASE=${TARGET_DB} \
PYTHONPATH=/lib \
  python3 -m unittest -v test_restore.TestRestore
