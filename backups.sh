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

#
# Loop through each pg database backing it up
#
#echo "Databases to backup: ${DBLIST}" >> /var/log/cron.log
for DB in ${DBLIST}
do
  echo "Backing up $DB"  >> /var/log/cron.log
  if [ -z "${ARCHIVE_FILENAME:-}" ]; then
  	FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
  else
  	FILENAME="${ARCHIVE_FILENAME}.${DB}.dmp"
  fi
  if [[  -f ${MYBASEDIR}/globals.sql ]]; then
    rm ${MYBASEDIR}/globals.sql
    pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
  else
    echo "Dump users and permisions"
    pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
  fi
  pg_dump -Fc -f ${FILENAME}  ${DB}
done

if [ "${REMOVE_BEFORE:-}" ]; then
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))

  echo "Removing following backups older than ${REMOVE_BEFORE} days" >> /var/log/cron.log
  find ${MYBASEDIR}/* -type f -mmin +${TIME_MINUTES} -delete &>> /var/log/cron.log
fi
