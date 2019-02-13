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

DBLIST=`psql -l | awk '$1 !~ /[+(|:]|Name|List|template|postgres/ {print $1}'`
# echo "Databases to backup: ${DBLIST}" >> /var/log/cron.log
for DB in ${DBLIST}
do
  echo "Backing up $DB"  >> /var/log/cron.log
  FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
  pg_dump -Fc -f ${FILENAME}  ${DB}
  if [[  -f ${MYBASEDIR}/globals.sql ]]; then
        rm ${MYBASEDIR}/globals.sql
        pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
  else
        echo "globals not found"
        pg_dumpall  --globals-only -f ${MYBASEDIR}/globals.sql
  fi

done
