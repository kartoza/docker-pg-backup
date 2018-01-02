#!/bin/bash

source /pgenv.sh

#echo "Running with these environment options" >> /var/log/cron.log
#set | grep PG >> /var/log/cron.log

if [ $ODOO_FILES -eq 1 ]; then
  MYDATE=`date +%d-%B-%Y`
  MONTH=$(date +%B)
  YEAR=$(date +%Y)
  MYBASEDIR=/var/backup
  MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
  mkdir -p ${MYBACKUPDIR}
  cd ${MYBACKUPDIR}
  FILENAME=${MYBACKUPDIR}/varlib.${MYDATE}.tar.gz

  echo "Backing up /var/lib/odoo"
  ACTION="Create $FILENAME in $MYBACKUPDIR"
  cp -R /var/lib/odoo /tmp/ && tar -zcf $FILENAME /tmp/odoo && rm -rf /tmp/odoo
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
    cp -f /var/credentials/credentials.json .gd/credentials.json
    ACTION="Copy $FILENAME to GDrive"
    /go/bin/drive push -destination $DRIVE_DESTINATION -ignore-checksum=false -quiet $FILENAME
    if [ $? -eq 0 ]; then
      echo "OK: " $ACTION " - " $(date)
    else
      echo "FAIL: " $ACTION " - " $(date)
    fi
    cp -f .gd/credentials.json /var/credentials/credentials.json
  else
    echo "DRIVE UPLOAD DISABLED"
  fi
else
  echo "ODOO FILES DISABLED"
fi