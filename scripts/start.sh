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


if [ -z "${PG_CONN_PARAMETERS}" ]; then
  PG_CONN_PARAMETERS="-h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER}"
fi

# How old can files and dirs be before getting trashed? In minutes
if [ -z "${DBLIST}" ]; then

  until PGPASSWORD=${POSTGRES_PASS} pg_isready ${PG_CONN_PARAMETERS}; do
    sleep 1
  done
  DBLIST=$(PGPASSWORD=${POSTGRES_PASS} psql ${PG_CONN_PARAMETERS} -l | awk '$1 !~ /[+(|:]|Name|List|template|postgres/ {print $1}')
fi

function cron_config() {
  if [[ ! -f /backup-scripts/backups-cron ]]; then
    # If it doesn't exists, copy from ${EXTRA_CONF_DIR} directory if exists
    if [[ -f ${EXTRA_CONFIG_DIR}/backups-cron ]]; then
      cp -f ${EXTRA_CONFIG_DIR}/backups-cron /backup-scripts
    else
      # default value
      if [ -z "${CRON_SCHEDULE}" ]; then
            cp /build_data/backups-cron-default /backup-scripts/backups-cron
      else
            envsubst < /build_data/backups-cron > /backup-scripts/backups-cron
       fi
    fi
  fi

}

mkdir -p ${DEFAULT_EXTRA_CONF_DIR}
# Copy settings for cron file

cron_config

function configure_env_variables() {
echo "
export PATH=\"${PATH}\"
export EXTRA_CONF_DIR=\"${EXTRA_CONF_DIR}\"
export STORAGE_BACKEND=\"${STORAGE_BACKEND}\"
export ACCESS_KEY_ID=\"${ACCESS_KEY_ID}\"
export SECRET_ACCESS_KEY=\"${SECRET_ACCESS_KEY}\"
export DEFAULT_REGION=\"${DEFAULT_REGION}\"
export BUCKET=\"${BUCKET}\"
export HOST_BASE=\"${HOST_BASE}\"
export HOST_BUCKET=\"${HOST_BUCKET}\"
export SSL_SECURE=\"${SSL_SECURE}\"
export DUMP_ARGS=\"${DUMP_ARGS}\"
export RESTORE_ARGS=\"${RESTORE_ARGS}\"
export POSTGRES_USER=\"${POSTGRES_USER}\"
export POSTGRES_PASS=\"$POSTGRES_PASS\"
export POSTGRES_PORT="${POSTGRES_PORT}"
export POSTGRES_HOST=\"${POSTGRES_HOST}\"
export DUMPPREFIX=\"${DUMPPREFIX}\"
export ARCHIVE_FILENAME=\"${ARCHIVE_FILENAME}\"
export REMOVE_BEFORE="${REMOVE_BEFORE}"
export PG_CONN_PARAMETERS=\"${PG_CONN_PARAMETERS}\"
export DBLIST=\"${DBLIST}\"
 " > /backup-scripts/pgenv.sh
echo "Start script running with these environment options"
set | grep PG

}
configure_env_variables
# Fix variables not interpolated
sed -i "s/'//g" /backup-scripts/backups-cron
sed -i 's/\"//g' /backup-scripts/backups-cron

# Setup cron job
crontab /backup-scripts/backups-cron

cron -f
