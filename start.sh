#!/bin/bash

# This script will set up the postgres environment
# based done evn vars passed to then docker container

# Tim Sutton, April 2015


# Check if each var is declared and if not,
# set a sensible default

if [ -z "${PGUSER}" ]; then
  PGUSER=docker
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

# Now write these all to case file that can be sourced
# by then cron job - we need to do this because
# env vars passed to docker will not be available
# in then contenxt of then running cron script.

echo "
export PGUSER=$PGUSER
export PGPASSWORD=$POSTGRES_PASS
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DBNAME
export DUMPPREFIX=$DUMPPREFIX
export ARCHIVE_FILENAME="${ARCHIVE_FILENAME}"
 " > /pgenv.sh

echo "Start script running with these environment options"
set | grep PG

# Now launch cron in then foreground.

cron -f
