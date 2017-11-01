#!/bin/bash

source /pgenv.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

MYDATE=`date +%d-%B-%Y-%H`
MONTH=$(date +%B)
YEAR=$(date +%Y)
MYBASEDIR=/var/backup
MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
mkdir -p ${MYBACKUPDIR}
cd ${MYBACKUPDIR}

echo "Backup running to $MYBACKUPDIR"

#
# Loop through each pg database backing it up
#

DBLIST=`psql -l | awk '{print $1}' | grep -v "+" | grep -v "Name" | grep -v "List" | grep -v "(" | grep -v "template" | grep -v "postgres" | grep -v "|" | grep -v ":"`
# echo "Databases to backup: ${DBLIST}" >> /var/log/cron.log
for DB in ${DBLIST}
do
  echo "Backing up $DB"
  FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.tar
  ACTION="Create $FILENAME in /backup"
  pg_dump -Ft -C -f ${FILENAME} -O ${DB} && gzip -f ${FILENAME}
  if [ $? -eq 0 ]; then
     echo "OK: " $ACTION " - " $(date)
  else
     echo "FAIL: " $ACTION " - " $(date)
  fi
  if [ -n "${DRIVE_DESTINATION}" ]; then
    if [ -d ".gd" ]; then
      echo ".gd directory exist";
    else 
      mkdir .gd
    fi
    cp -f /var/credentials.json .gd/credentials.json
    ACTION="Copy $FILENAME to GDrive"
    /go/bin/drive push -destination $DRIVE_DESTINATION -ignore-checksum=false -quiet $FILENAME.gz
    if [ $? -eq 0 ]; then
      echo "OK: " $ACTION " - " $(date)
    else
      echo "FAIL: " $ACTION " - " $(date)
    fi
    cp -f .gd/credentials.json /var/credentials.json
  else 
    echo "DRIVE UPLOAD DISABLED"
  fi
done
