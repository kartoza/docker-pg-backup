#!/bin/bash

source /pgenv.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

MYDATE=`date +%d-%B-%Y`
MONTH=$(date +%B)
YEAR=$(date +%Y)
MYBASEDIR=/backups
MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
mkdir -p ${MYBACKUPDIR}
cd ${MYBACKUPDIR}

echo "Backup running to $MYBACKUPDIR" >> /var/log/cron.log

# Backup globals Always get the latest
pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql


# Loop through each pg database backing it up

for DB in ${DBLIST}
do
  echo "Backing up $DB"  >> /var/log/cron.log
  if [ -z "${ARCHIVE_FILENAME:-}" ]; then
  	FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
  else
  	FILENAME="${ARCHIVE_FILENAME}.${DB}.dmp"
  fi
  pg_dump -Fc -f ${FILENAME}  ${DB}
done

if [ "${REMOVE_BEFORE:-}" ]; then
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))

  echo "Removing following backups older than ${REMOVE_BEFORE} days" >> /var/log/cron.log
  find ${MYBASEDIR}/* -type f -mmin +${TIME_MINUTES} -delete &>> /var/log/cron.log
fi
