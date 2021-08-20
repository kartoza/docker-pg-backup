#!/bin/bash

source /backup-scripts/env-data.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

MYDATE=$(date +%d-%B-%Y)
MONTH=$(date +%B)
YEAR=$(date +%Y)

MYBASEDIR=/${BUCKET}
MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
mkdir -p ${MYBACKUPDIR}
cd ${MYBACKUPDIR}

export HOST_BASE HOST_BUCKET DEFAULT_REGION SSL_SECURE ACCESS_KEY_ID SECRET_ACCESS_KEY

if [[ ${STORAGE_BACKEND} == "S3" ]]; then
  s3_config
  s3cmd mb s3://${BUCKET}
fi

echo "Backup running to $MYBACKUPDIR" >>/var/log/cron.log

# Backup globals Always get the latest

if [[ ${STORAGE_BACKEND} =~ [Ff][Ii][Ll][Ee] ]]; then
  PGPASSWORD=${POSTGRES_PASS} pg_dumpall ${PG_CONN_PARAMETERS}  --globals-only -f ${MYBASEDIR}/globals.sql
elif [[ ${STORAGE_BACKEND} == "S3" ]]; then
  PGPASSWORD=${POSTGRES_PASS} pg_dumpall ${PG_CONN_PARAMETERS}  --globals-only | s3cmd put - s3://${BUCKET}/globals.sql
  echo "Sync globals.sql to ${BUCKET} bucket  " >>/var/log/cron.log
fi

# Loop through each pg database backing it up

for DB in ${DBLIST}; do
  echo "Backing up $DB" >>/var/log/cron.log
  if [ -z "${ARCHIVE_FILENAME:-}" ]; then
    FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
  else
    FILENAME=${MYBASEDIR}/"${ARCHIVE_FILENAME}.${DB}.dmp"
  fi
  if [[ ${STORAGE_BACKEND} =~ [Ff][Ii][Ll][Ee] ]]; then
    if [ -z "${DB_TABLES:-}" ]; then
      PGPASSWORD=${POSTGRES_PASS} pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS}  -d ${DB} > ${FILENAME}
    else
      dump_tables ${DB} ${DUMP_ARGS} ${MYDATE} ${MYBACKUPDIR}
    fi
    echo "Backing up $FILENAME" >>/var/log/cron.log
  elif [[ ${STORAGE_BACKEND} == "S3" ]]; then
    if [ -z "${DB_TABLES:-}" ]; then
      echo "Backing up $FILENAME to s3://${BUCKET}/" >>/var/log/cron.log
      PGPASSWORD=${POSTGRES_PASS} pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d ${DB} > ${FILENAME}
      gzip $FILENAME
      s3cmd sync -r ${MYBASEDIR}/* s3://${BUCKET}/
      echo "Backing up $FILENAME done" >>/var/log/cron.log
      rm ${MYBACKUPDIR}/*
    else
      dump_tables ${DB} ${DUMP_ARGS} ${MYDATE} ${MYBACKUPDIR}
      s3cmd sync -r ${MYBASEDIR}/* s3://${BUCKET}/
      rm ${MYBACKUPDIR}/*
    fi

  fi

done

if [ "${REMOVE_BEFORE:-}" ]; then
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))
  if [[ ${STORAGE_BACKEND} == "FILE" ]]; then
    echo "Removing following backups older than ${REMOVE_BEFORE} days" >>/var/log/cron.log
    find ${MYBASEDIR}/* -type f -mmin +${TIME_MINUTES} -delete &>>/var/log/cron.log
  elif [[ ${STORAGE_BACKEND} == "S3" ]]; then
    # Credits https://shout.setfive.com/2011/12/05/deleting-files-older-than-specified-time-with-s3cmd-and-bash/
    clean_s3bucket "${BUCKET}" "${REMOVE_BEFORE} days"
  fi
fi
