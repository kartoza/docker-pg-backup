#!/bin/bash


MYDATE=`date +%d-%B-%Y`
MONTH=$(date +%B)
YEAR=$(date +%Y)
MYBASEDIR=/backups
MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
mkdir -p $MYBACKUPDIR
cd $MYBACKUPDIR

echo "Backup running to $MYBACKUPDIR" >> /var/log/cron.log

#
# Loop through each pg database backing it up
#

DBLIST=`psql -l | awk '{print $1}' | grep -v "+" | grep -v "Name" | grep -v "List" | grep -v "(" | grep -v "template" | grep -v "postgres" | grep -v ":"`
for DB in ${DBLIST}
do
  echo "Backing up $DB" 
  FILENAME=${MYBACKUPDIR}/PG_${DB}.${MYDATE}.dmp
  pg_dump -i -Fc -f ${FILENAME} -x -O ${DB}"
done
