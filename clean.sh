#!/bin/bash

source /pgenv.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

MONTH=$(date +%B --date='-1 month')
YEAR=$(date +%Y --date='-1 month')
MYBASEDIR=/var/backup
MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
cd ${MYBACKUPDIR}

echo "Cleaning running to $MYBACKUPDIR"

#
# Loop through each pg database backing it up
#

  ACTION="Clean $MYBACKUPDIR in /backup"
  (ls -t|head -n 5;ls)|sort|uniq -u|xargs rm
  if [ $? -eq 0 ]; then
     echo "OK: " $ACTION " - " $(date)
  else
     echo "FAIL: " $ACTION " - " $(date)
  fi
