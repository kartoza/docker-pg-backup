#!/bin/bash

# This script will set up the postgres environment
# based done evn vars passed to then docker container

# Tim Sutton, April 2015


# Check if each var is declared and if not,
# set a sensible default

if [ -z "${PGUSER}" ]; then
  PGUSER=docker
fi

if [ -z "${PGPASSWORD}" ]; then
  PGPASSWORD=docker
fi

if [ -z "${PGPORT}" ]; then
  PGPORT=5432
fi

if [ -z "${PGHOST}" ]; then
  PGHOST=db
fi

if [ -z "${PGDATABASE}" ]; then
  PGDATABASE=gis
fi

if [ -z "${DUMPPREFIX}" ]; then
  DUMPPREFIX=PG
fi

if [ -z "${DAILY}" ]; then
  DAILY=7
fi

if [ -z "${MONTHLY}" ]; then
  MONTHLY=12
fi

if [ -z "${YEARLY}" ]; then
  YEARLY=3
fi

if [ -z "${USE_SFTP_BACKUP}" ]; then
  USE_SFTP_BACKUP=False
fi

if [ -z "${SFTP_USER}" ]; then
  SFTP_USER=user
fi

if [ -z "${SFTP_PASSWORD}" ]; then
  SFTP_PASSWORD=password
fi

if [ -z "${SFTP_HOST}" ]; then
  SFTP_HOST=localhost
fi

if [ -z "${SFTP_DIR}" ]; then
  SFTP_DIR="/"
fi

# Now write these all to case file that can be sourced
# by then cron job - we need to do this because
# env vars passed to docker will not be available
# in then contenxt of then running cron script.

echo "
export PGUSER=$PGUSER
export PGPASSWORD=$PGPASSWORD
export PGPORT=$PGPORT
export PGHOST=$PGHOST
export PGDATABASE=$PGDATABASE
export DUMPPREFIX=$DUMPPREFIX
export DAILY=$DAILY
export MONTHLY=$MONTHLY
export YEARLY=$YEARLY
export USE_SFTP_BACKUP=$USE_SFTP_BACKUP
export SFTP_HOST=$SFTP_HOST
export SFTP_USER=$SFTP_USER
export SFTP_PASSWORD=$SFTP_PASSWORD
export SFTP_DIR=$SFTP_DIR
 " > /pgenv.sh

echo "Start script running with these environment options"
set | grep PG

# Now launch cron in then foreground.

cron -f

if [ "$1" == "push-to-remote-sftp" ]; then
  # push all local backup files to remote sftp server
  python -c "from sftp_remote import push_backups_to_remote; push_backups_to_remote()"
fi

if [ "$1" == "pull-from-remote-sftp" ]; then
  # pull all remote sftp backup files to local server
  python -c "from sftp_remote import pull_backups_from_remote; pull_backups_from_remote()"
fi
