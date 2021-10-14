#!/bin/bash

DEFAULT_EXTRA_CONF_DIR="/settings"

function file_env {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}


if [ -z "${EXTRA_CONF_DIR}" ]; then
  EXTRA_CONF_DIR=${DEFAULT_EXTRA_CONF_DIR}
fi

if [ -z "${STORAGE_BACKEND}" ]; then
	STORAGE_BACKEND="FILE"
fi

file_env 'ACCESS_KEY_ID'

if [ -z "${ACCESS_KEY_ID}" ]; then
	ACCESS_KEY_ID=
fi

file_env 'SECRET_ACCESS_KEY'
if [ -z "${SECRET_ACCESS_KEY}" ]; then
	SECRET_ACCESS_KEY=
fi
if [ -z "${DEFAULT_REGION}" ]; then
	DEFAULT_REGION=us-west-2
fi

if [ -z "${BUCKET}" ]; then
	BUCKET=backups
fi
file_env 'HOST_BASE'
if [ -z "${HOST_BASE}" ]; then
	HOST_BASE=
fi

if [ -z "${HOST_BUCKET}" ]; then
	HOST_BUCKET=
fi
if [ -z "${SSL_SECURE}" ]; then
	SSL_SECURE=True
fi
if [ -z "${DUMP_ARGS}" ]; then
	 DUMP_ARGS='-Fc'
fi
if [ -z "${RESTORE_ARGS}" ]; then
	RESTORE_ARGS='-j 4'
fi

file_env 'POSTGRES_USER'
if [ -z "${POSTGRES_USER}" ]; then
  POSTGRES_USER=docker
fi
file_env 'POSTGRES_PASS'
if [ -z "${POSTGRES_PASS}" ]; then
  POSTGRES_PASS=docker
fi

if [ -z "${POSTGRES_PORT}" ]; then
  POSTGRES_PORT=5432
fi

if [ -z "${POSTGRES_HOST}" ]; then
  POSTGRES_HOST=db
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

if [ -z "${CRON_SCHEDULE}" ]; then
  CRON_SCHEDULE="0 23 * * *"
fi

if [ -z "${PG_CONN_PARAMETERS}" ]; then
  PG_CONN_PARAMETERS="-h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER}"
fi

# How old can files and dirs be before getting trashed? In minutes
if [ -z "${DBLIST}" ]; then
  DBLIST=$(PGPASSWORD=${POSTGRES_PASS} psql ${PG_CONN_PARAMETERS} -l | awk '$1 !~ /[+(|:]|Name|List|template|postgres/ {print $1}')
fi



function s3_config() {
  if [[ ! -f /root/.s3cfg ]]; then
    # If it doesn't exists, copy from ${EXTRA_CONF_DIR} directory if exists
    if [[ -f ${EXTRA_CONFIG_DIR}/s3cfg ]]; then
      cp -f ${EXTRA_CONFIG_DIR}/s3cfg /root/.s3cfg
    else
      # default value
      envsubst < /build_data/s3cfg > /root/.s3cfg
    fi
  fi

}

# Cleanup S3 bucket
function clean_s3bucket() {
  S3_BUCKET=$1
  DEL_DAYS=$2
  s3cmd ls s3://${S3_BUCKET} --recursive | while read -r line; do
    createDate=$(echo $line | awk {'print ${S3_BUCKET}" "${DEL_DAYS}'})
    createDate=$(date -d"$createDate" +%s)
    olderThan=$(date -d"-${S3_BUCKET}" +%s)
    if [[ $createDate -lt $olderThan ]]; then
      fileName=$(echo $line | awk {'print $4'})
      echo $fileName
      if [[ $fileName != "" ]]; then
        s3cmd del "$fileName"
      fi
    fi
  done
}

function dump_tables() {
  DATABASE=$1
  DATABASE_DUMP_OPTIONS=$2
  TIME_STAMP=$3
  DATA_PATH=$4
  array=($(PGPASSWORD=${POSTGRES_PASS} psql ${PG_CONN_PARAMETERS} -d ${DATABASE} -At --field-separator '.' -c "SELECT table_schema,table_name FROM information_schema.tables
where table_schema not in ('information_schema','pg_catalog','topology') and table_name
not in ('raster_columns','raster_overviews','spatial_ref_sys', 'geography_columns', 'geometry_columns')
ORDER BY table_schema,table_name;"))
  for i in "${array[@]}"; do
    #TODO split the variable i to get the schema and table names separately so that we can quote them to avoid weird table
    # names and schema names
    PGPASSWORD=${POSTGRES_PASS} pg_dump ${PG_CONN_PARAMETERS} -d ${DATABASE} ${DATABASE_DUMP_OPTIONS} -t $i >$DATA_PATH/${DATABASE}_${i}_${TIME_STAMP}.dmp
  done
}

function cron_config() {
  if [[ ! -f /backup-scripts/backups-cron ]]; then
    # If it doesn't exists, copy from ${EXTRA_CONF_DIR} directory if exists
    if [[ -f ${EXTRA_CONFIG_DIR}/backups-cron ]]; then
      cp -f ${EXTRA_CONFIG_DIR}/backups-cron /backup-scripts
    else
      # default value
      envsubst < /build_data/backups-cron > /backup-scripts/backups-cron
    fi
  fi

}

