#!/usr/bin/env bash
set -euo pipefail

source /backup-scripts/pgenv.sh
DB=gis

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------
: "${MONTH:=$(date +%B)}"
: "${YEAR:=$(date +%Y)}"
: "${MYBASEDIR:=/${BUCKET:-backups}}"
: "${MYBACKUPDIR:=${MYBASEDIR}/${YEAR}/${MONTH}}"

# ------------------------------------------------------------------
# Find exactly one base .dmp.gz file
# ------------------------------------------------------------------
shopt -s nullglob
files=("${MYBACKUPDIR}"/*.dmp.gz)
shopt -u nullglob

if (( ${#files[@]} != 1 )); then
  echo "ERROR: Expected exactly one base .dmp file, found ${#files[@]}"
  exit 1
fi

BASE_FILENAME="${files[0]}"
file_name="$(basename "$BASE_FILENAME")"

# ------------------------------------------------------------------
# Parse filename date safely
# PG_gis_gis.24-December-2025-16-46.dmp.gz
# ------------------------------------------------------------------
datetime_part="${file_name%.dmp.gz}"
datetime_part="${datetime_part##*.}"

IFS='-' read -r DAY MONTH_NAME YEAR HOUR MINUTE <<< "$datetime_part"

case "$MONTH_NAME" in
  January)   MONTH_NUM=01 ;;
  February)  MONTH_NUM=02 ;;
  March)     MONTH_NUM=03 ;;
  April)     MONTH_NUM=04 ;;
  May)       MONTH_NUM=05 ;;
  June)      MONTH_NUM=06 ;;
  July)      MONTH_NUM=07 ;;
  August)    MONTH_NUM=08 ;;
  September) MONTH_NUM=09 ;;
  October)   MONTH_NUM=10 ;;
  November)  MONTH_NUM=11 ;;
  December)  MONTH_NUM=12 ;;
  *)
    echo "ERROR: Unknown month name '$MONTH_NAME' in filename"
    exit 1
    ;;
esac

DATE="${YEAR}-${MONTH_NUM}-${DAY}"
DATETIME="${YEAR}-${MONTH_NUM}-${DAY}-${HOUR}-${MINUTE}"

if [[ ${RESTORE_DATE:-} =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  export TARGET_ARCHIVE_DATE_ONLY="${DATE}"
  printf 'export %s="%s"\n' "TARGET_ARCHIVE_DATE_ONLY" "${TARGET_ARCHIVE_DATE_ONLY}" >> /backup-scripts/pgenv.sh


elif [[ ${RESTORE_DATE_TIME:-} =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  export TARGET_ARCHIVE_DATETIME="${DATETIME}"
  printf 'export %s="%s"\n' "TARGET_ARCHIVE_DATETIME" "${TARGET_ARCHIVE_DATETIME}" >> /backup-scripts/pgenv.sh

else
  echo "No param assigned"
fi



