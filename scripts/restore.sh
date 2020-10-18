#!/bin/bash

source /pgenv.sh

echo "TARGET_DB: ${TARGET_DB}"
echo "WITH_POSTGIS: ${WITH_POSTGIS}"
echo "TARGET_ARCHIVE: ${TARGET_ARCHIVE}"

if [ -z "${TARGET_ARCHIVE:-}" ] || [ ! -f "${TARGET_ARCHIVE:-}" ]; then
	echo "TARGET_ARCHIVE needed."
	exit 1
fi

if [ -z "${TARGET_DB:-}" ]; then
	echo "TARGET_DB needed."
	exit 1
fi

echo "Dropping target DB"
dropdb ${TARGET_DB}

if [ -z "${WITH_POSTGIS:-}" ]; then
	echo "Recreate target DB without POSTGIS"
	createdb -O ${PGUSER} ${TARGET_DB}
else
	echo "Recreate target DB with POSTGIS"
	createdb -O ${PGUSER}  ${TARGET_DB}
	psql -c 'CREATE EXTENSION IF NOT EXISTS postgis;' ${TARGET_DB}
fi

echo "Restoring dump file"
psql -f /backups/globals.sql ${TARGET_DB}
pg_restore ${TARGET_ARCHIVE} | psql -d ${TARGET_DB}
