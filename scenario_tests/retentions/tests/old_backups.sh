#!/usr/bin/env bash
set -euo pipefail

source /backup-scripts/pgenv.sh
DB=gis



if [ -z "${MONTH:-}" ]; then
  export MONTH="$(date +%B)"
fi

if [ -z "${YEAR:-}" ]; then
  export YEAR="$(date +%Y)"
fi

if [ -z "${MYBASEDIR:-}" ]; then
  export MYBASEDIR="/${BUCKET:-backups}"
fi

if [ -z "${MYBACKUPDIR:-}" ]; then
  export MYBACKUPDIR="${MYBASEDIR}/${YEAR}/${MONTH}"
fi


for list in ${MYBACKUPDIR}/*.dmp;do
  backup_dir_filename=${list}
  file_name=$(basename "${backup_dir_filename}")
  datetime_part=$(basename "$file_name" .dmp | cut -d. -f2)
  base_date="$(sed 's/-/ /1; s/-/ /1; s/-/ /1; s/-/:/' <<< "$datetime_part")"

done

BASE_FILENAME="${MYBACKUPDIR}/${file_name}"


for i in {0..7}; do
  OLDDATE=$(date -d "$base_date -$i day" +%d-%B-%Y-%H-%M)
  echo "the old date is $OLDDATE"
  OLD_BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${OLDDATE}.dmp"
  OLD_BASE_FILENAME_ZIP="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${OLDDATE}.dmp.gz"
  echo $OLD_BASE_FILENAME

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