#!/bin/bash

source /pgenv.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

function s3_config() {
  if [[ -f /root/.aws/credentials ]]; then
    rm /root/.aws/credentials
  fi

  cat >/root/.aws/credentials <<EOF
[default]
aws_access_key=${WS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF

if [[ -f ${AWS_CONFIG_FILE} ]]; then
    rm ${AWS_CONFIG_FILE}
fi
 cat >${AWS_CONFIG_FILE} <<EOF
[default]
region=${AWS_DEFAULT_REGION}
output=${AWS_DEFAULT_OUTPUT}
EOF
}

MYDATE=`date +%d-%B-%Y`
MONTH=$(date +%B)
YEAR=$(date +%Y)
if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
  MYBASEDIR=/backups
  MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
  mkdir -p ${MYBACKUPDIR}
  cd ${MYBACKUPDIR}
elif [[ ${STORAGE_BACKEND} == 'AWS' ]]; then
  MYBASEDIR=${S3_BUCKET}
  MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
  s3_config
  aws s3 mb s3://${MYBACKUPDIR}
fi




#
# Loop through each pg database backing it up
#
#echo "Databases to backup: ${DBLIST}" >> /var/log/cron.log
# Dump globals and sync to S3 bucket if available
if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
  echo "Backup globals  to ${MYBASEDIR}/globals.sql" >> /var/log/cron.log
  pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
elif [[ ${STORAGE_BACKEND} == 'AWS' ]]; then
  pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
  aws s3 cp ${MYBASEDIR}/globals.sql s3://${MYBASEDIR}/
  echo "Sync globals to S3 bucket  ${MYBASEDIR}/globals.sql" >> /var/log/cron.log
fi

# loop through all DB and dump them
for DB in ${DBLIST}
do
  echo "Backing up $DB"  >> /var/log/cron.log
  if [ -z "${ARCHIVE_FILENAME:-}" ]; then
  	FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
  else
  	FILENAME="${ARCHIVE_FILENAME}.${DB}.dmp"
  fi
  if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
      pg_dump -Fc -f ${FILENAME}  ${DB}
      echo "Backing up $FILENAME"  >> /var/log/cron.log
  elif [[ ${STORAGE_BACKEND} == 'AWS' ]]; then
      pg_dump -Fc -f ${FILENAME}  ${DB}
      aws s3 cp ${FILENAME} s3://${MYBASEDIR}/
      echo "Finished syncing to AWS"
      echo "Sync DB ${DB} as ${FILENAME} to ${S3_BUCKET}" >> /var/log/cron.log
      rm ${FILENAME}
  fi

done

if [ "${REMOVE_BEFORE:-}" ]; then
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))
  echo "Removing following backups older than ${REMOVE_BEFORE} days" >> /var/log/cron.log
  if [[ ${STORAGE_BACKEND} == 'FILE' ]];then
    find ${MYBASEDIR}/* -type f -mmin +${TIME_MINUTES} -delete &>> /var/log/cron.log
  elif [[ ${STORAGE_BACKEND} == 'AWS' ]]; then
    for file in  find $(aws s3 ls 's3://${MYBASEDIR}/*') -type f -mmin +${TIME_MINUTES};
    do
      aws s3 rm --recursive s3://${MYBASEDIR}/07-30-2019/$file;
    done
  fi
fi
