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
# Find exactly one base .dmp file
# ------------------------------------------------------------------
shopt -s nullglob
files=("${MYBACKUPDIR}"/*.dmp)
shopt -u nullglob

if (( ${#files[@]} != 1 )); then
  echo "ERROR: Expected exactly one base .dmp file, found ${#files[@]}"
  exit 1
fi

BASE_FILENAME="${files[0]}"
file_name="$(basename "$BASE_FILENAME")"

# ------------------------------------------------------------------
# Parse filename date safely
# PG_gis_gis.24-December-2025-16-46.dmp
# ------------------------------------------------------------------
datetime_part="${file_name%.dmp}"
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

# ISO timestamp (portable)
ISO_TS="${YEAR}-${MONTH_NUM}-${DAY} ${HOUR}:${MINUTE}"

BASE_EPOCH=$(date -d "$ISO_TS" +%s 2>/dev/null || true)

if [[ -z "$BASE_EPOCH" ]]; then
  echo "ERROR: Failed to parse ISO date '$ISO_TS'"
  exit 1
fi

echo "Base backup timestamp: $(date -d "@$BASE_EPOCH")"

# ------------------------------------------------------------------
# Generate mock backups (0–7 days old)
# ------------------------------------------------------------------
for i in {0..7}; do
  OLD_EPOCH=$(( BASE_EPOCH - i * 86400 ))
  OLDER_DATE=$(date -d "@$OLD_EPOCH" +%d-%B-%Y-%H-%M)

  OLD_BASE_FILENAME="${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${OLDER_DATE}.dmp"

  cp -n "$BASE_FILENAME" "$OLD_BASE_FILENAME"
  touch -d "@$OLD_EPOCH" "$OLD_BASE_FILENAME"

  if [[ ${STORAGE_BACKEND} == 'S3' ]]; then
    gzip -9 -c "$OLD_BASE_FILENAME" > "${OLD_BASE_FILENAME}.gz"
    touch -d "@$OLD_EPOCH" "${OLD_BASE_FILENAME}.gz"

    source /backup-scripts/lib/logging.sh
    source /backup-scripts/lib/utils.sh
    source /backup-scripts/lib/s3.sh
    init_logging
    s3_upload "${OLD_BASE_FILENAME}.gz"
  fi

  echo "Created mock backup ($i days old): ${OLD_BASE_FILENAME}"
done