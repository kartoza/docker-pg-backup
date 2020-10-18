#!/bin/bash

# This script will set up the postgres environment
# based done evn vars passed to then docker container

# Tim Sutton, April 2015

# Check if each var is declared and if not,
# set a sensible default
if [ -z "${POSTGRES_USER}" ]; then
  POSTGRES_USER=docker
fi

if [ -z "${POSTGRES_PASS}" ]; then
  POSTGRES_PASS=docker
fi

if [ -z "${POSTGRES_PORT}" ]; then
  POSTGRES_PORT=5432
fi

if [ -z "${POSTGRES_HOST}" ]; then
  POSTGRES_HOST=db
fi

if [ -z "${POSTGRES_DBNAME}" ]; then
  POSTGRES_DBNAME=gis
fi

if [ -z "${DUMPPREFIX}" ]; then
  DUMPPREFIX=PG
fi

if [ -z "${ARCHIVE_FILENAME}" ]; then
  ARCHIVE_FILENAME=
fi

# How old can files and dirs be before getting trashed? In minutes
if [ -z "${REMOVE_BEFORE}" ]; then
  REMOVE_BEFORE=
fi

# How old can files and dirs be before getting trashed? In minutes
if [ -z "${DBLIST}" ]; then
  DBLIST=$(PGPASSWORD=${POSTGRES_PASS} psql -h $POSTGRES_HOST -p 5432 -U $POSTGRES_USER -l | awk '$1 !~ /[+(|:]|Name|List|template|postgres/ {print $1}')
fi

# Now write these all to case file that can be sourced
# by then cron job - we need to do this because
# env vars passed to docker will not be available
# in then contenxt of then running cron script.

PG_ENV="/pgenv.sh"
if [[ -f "${PG_ENV}" ]]; then
  rm ${PG_ENV}
fi

echo "
export PGUSER=$POSTGRES_USER
export PGPASSWORD=\"$POSTGRES_PASS\"
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export DUMPPREFIX=$DUMPPREFIX
export ARCHIVE_FILENAME="${ARCHIVE_FILENAME}"
export REMOVE_BEFORE=$REMOVE_BEFORE
export DBLIST=\"$DBLIST\"
 " >/pgenv.sh
echo "Start script running with these environment options"
cat /pgenv.sh
set | grep PG

# Update cron script to add time
if [[ -f /backup-scripts/backups-cron ]]; then
    rm /backup-scripts/backups-cron
fi
cat >>/backup-scripts/backups-cron <<EOF
# Run the backups at 11pm each night
${CRON_SCHEDULE} /backup-scripts/backups.sh 2>&1

EOF

# Now launch cron in then foreground.
crontab /backup-scripts/backups-cron

cron -f
