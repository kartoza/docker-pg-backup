#!/usr/bin/env bash
set -euo pipefail

source /backup-scripts/pgenv.sh
DB=gis

BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp"

for i in {0..7}; do
  OLDDATE=$(date -d "-$i day" +%d-%B-%Y-%H-%M)
  OLD_BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${OLDDATE}.dmp"

  cp "$BASE_FILENAME" "$OLD_BASE_FILENAME"

  # makes retention work using mtime
  touch -d "$i days ago" "$OLD_BASE_FILENAME"

  echo "Created mock backup ($i days old): $OLD_BASE_FILENAME"
done