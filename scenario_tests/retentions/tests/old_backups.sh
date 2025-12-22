#!/usr/bin/env bash
set -euo pipefail

source /backup-scripts/pgenv.sh
DB=gis

BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp"

for i in {0..7}; do
  OLDDATE=$(date -d "-$i day" +%d-%B-%Y-%H-%M)
  OLD_BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${OLDDATE}.dmp"
  OLD_BASE_FILENAME_ZIP="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${OLDDATE}.dmp.gz"

  cp "$BASE_FILENAME" "$OLD_BASE_FILENAME"

  if [[ ${STORAGE_BACKEND} == 'S3' ]];then
    touch -d "$i days ago" "$OLD_BASE_FILENAME"
    gzip -9 -c "${OLD_BASE_FILENAME}" > "${OLD_BASE_FILENAME_ZIP}"
    touch -d "$i days ago" "$OLD_BASE_FILENAME_ZIP"
    source /backup-scripts/lib/logging.sh
    source /backup-scripts/lib/utils.sh
    source /backup-scripts/lib/s3.sh
    init_logging
    s3_upload "$OLD_BASE_FILENAME_ZIP"
  else
    touch -d "$i days ago" "$OLD_BASE_FILENAME"
  fi

  echo "Created mock backup ($i days old): $OLD_BASE_FILENAME"
done