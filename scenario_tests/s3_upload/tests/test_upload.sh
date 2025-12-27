#!/usr/bin/env bash

set -e

# execute tests
pushd /tests

PGHOST=localhost \
PGDATABASE=gis \
PYTHONPATH=/lib \
  python3 -m unittest -v test_upload.TestUpload


# Clean up artifact
s3cmd rm --force --recursive s3://${BUCKET}
