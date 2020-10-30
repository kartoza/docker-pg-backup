#!/bin/bash

source /pgenv.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

function minio_config() {
  if [[ -f /root/.s3cfg ]]; then
    rm /root/.s3cfg
  fi

  cat >/root/.s3cfg <<EOF
host_base = ${HOST_BASE}
host_bucket = ${HOST_BUCKET}
bucket_location = ${DEFAULT_REGION}
use_https = ${SSL_SECURE}

# Setup access keys
access_key =  ${ACCESS_KEY_ID}
secret_key = ${SECRET_ACCESS_KEY}

# Enable S3 v4 signature APIs
signature_v2 = False
${EXTRA_CONF}
EOF
}



MYDATE=`date +%d-%B-%Y`
MONTH=$(date +%B)
YEAR=$(date +%Y)

if [[ ${STORAGE_BACKEND} != 'FILE' ]];then
  MYBASEDIR=/${BUCKET}
  MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
  mkdir -p ${MYBACKUPDIR}
  cd ${MYBACKUPDIR}
elif [[ ${STORAGE_BACKEND} == 'AWS' ]]; then
  MYBACKUPDIR=${YEAR}/${MONTH}
  minio_config
  s3cmd mb s3://${BUCKET}

fi

echo "Backup running to $MYBACKUPDIR" >> /var/log/cron.log

# Backup globals Always get the latest


if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
  pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
else
  pg_dumpall --globals-only  | s3cmd put - s3://${BUCKET}/globals.sql
  echo "Sync globals.sql to ${BUCKET} bucket  " >> /var/log/cron.log
fi


# Loop through each pg database backing it up

for DB in ${DBLIST}
do
  echo "Backing up $DB"  >> /var/log/cron.log
  if [ -z "${ARCHIVE_FILENAME:-}" ]; then
  	FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
  else
    if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
  	  FILENAME=${MYBASEDIR}/"${ARCHIVE_FILENAME}.${DB}.dmp"
  	else
  	  FILENAME="${ARCHIVE_FILENAME}.${DB}.dmp"
  	fi
  fi
  if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
      pg_dump ${DUMP_ARGS} -f ${FILENAME}  ${DB}
      echo "Backing up $FILENAME"  >> /var/log/cron.log
  else
      pg_dump ${DUMP_ARGS} ${DB} -f ${FILENAME}
      s3cmd sync -r  ${FILENAME} s3://${BUCKET}/
      rm ${FILENAME}
  fi

done

if [ "${REMOVE_BEFORE:-}" ]; then
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))

  echo "Removing following backups older than ${REMOVE_BEFORE} days" >> /var/log/cron.log
  find ${MYBASEDIR}/* -type f -mmin +${TIME_MINUTES} -delete &>> /var/log/cron.log
fi
