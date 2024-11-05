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

if [ -z "${RUN_AS_ROOT}" ]; then
  RUN_AS_ROOT=true
fi

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

file_env 'DEFAULT_REGION'
if [ -z "${DEFAULT_REGION}" ]; then
	DEFAULT_REGION=us-west-2
fi

file_env 'BUCKET'
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

if [ -z "${RUN_ONCE}" ]; then
  RUN_ONCE=FALSE
fi

if [ -z "${DB_DUMP_ENCRYPTION}" ]; then
  DB_DUMP_ENCRYPTION=FALSE
fi

if [ -z "${CONSOLE_LOGGING}" ]; then
  CONSOLE_LOGGING=FALSE
fi

if [ -z "${DB_TABLES}" ]; then
  DB_TABLES=FALSE
fi

file_env 'DB_DUMP_ENCRYPTION_PASS_PHRASE'
if [ -z "${DB_DUMP_ENCRYPTION_PASS_PHRASE}" ]; then
  STRING_LENGTH=30
  random_pass_string=$(cat /dev/urandom | tr -dc '[:alnum:]' | head -c "${STRING_LENGTH}")
  DB_DUMP_ENCRYPTION_PASS_PHRASE=${random_pass_string}
  export DB_DUMP_ENCRYPTION_PASS_PHRASE
fi


function cron_config() {
  if [[ -f ${EXTRA_CONFIG_DIR}/backups-cron ]]; then
      envsubst < ${EXTRA_CONFIG_DIR}/backups-cron > /backup-scripts/backups-cron
  else
      # default value

      if [ -z "${CRON_SCHEDULE}" ]; then
        export CRON_SCHEDULE='0 24 * * *'
      fi
      envsubst < /build_data/backups-cron > /backup-scripts/backups-cron

  fi
}

function directory_checker() {
  DATA_PATH=$1
  if [ -d "$DATA_PATH" ];then
    DB_USER_PERM=$(stat -c '%U' "${DATA_PATH}")
    DB_GRP_PERM=$(stat -c '%G' "${DATA_PATH}")
    if [[ ${DB_USER_PERM} != "${USER}" ]] &&  [[ ${DB_GRP_PERM} != "${GROUP}"  ]];then
      chown -R "${USER}":"${GROUP}" "${DATA_PATH}"
    fi
  fi

}
function non_root_permission() {
  USER="$1"
  GROUP="$2"
  services=("${DEFAULT_EXTRA_CONF_DIR}" "/build_data" "/root/" "/backups" "/etc" "/var/log" "/var/run/" "/usr/lib" "/usr/bin/")
  for paths in "${services[@]}"; do
    directory_checker "${paths}"
  done
}


mkdir -p ${DEFAULT_EXTRA_CONF_DIR}
# Copy settings for cron file
if [[ ${CONSOLE_LOGGING} =~ [Tt][Rr][Uu][Ee] ]];then
   export CONSOLE_LOGGING_OUTPUT='/proc/1/fd/1 2>&1'
else
   export CONSOLE_LOGGING_OUTPUT='/var/log/cron.out 2>&1'
fi

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
export RUN_ONCE="${RUN_ONCE}"
DB_DUMP_ENCRYPTION_PASS_PHRASE=\"${DB_DUMP_ENCRYPTION_PASS_PHRASE}\"
DB_DUMP_ENCRYPTION="${DB_DUMP_ENCRYPTION}"
export PG_CONN_PARAMETERS=\"${PG_CONN_PARAMETERS}\"
export DBLIST=\"${DBLIST}\"
export DB_TABLES=\"${DB_TABLES}\"
 " > /backup-scripts/pgenv.sh

echo "Start script running with these environment options"
set | grep PG

}
configure_env_variables

if [[ ${CONSOLE_LOGGING} =~ [Tt][Rr][Uu][Ee] ]];then
   sed -i 's#${CONSOLE_LOGGING_OUTPUT}#/proc/1/fd/1 2>\&1#g' /backup-scripts/backups.sh
else
   sed -i 's#${CONSOLE_LOGGING_OUTPUT}#/var/log/cron.out 2>\&1#g' /backup-scripts/backups.sh
fi

# Fix variables not interpolated
sed -i "s/'//g" /backup-scripts/backups-cron
sed -i 's/\"//g' /backup-scripts/backups-cron

# Setup cron job

# Gosu preparations
if [[ ${RUN_AS_ROOT} =~ [Ff][Aa][Ll][Ss][Ee] ]];then
  USER_ID=${POSTGRES_UID:-1000}
  GROUP_ID=${POSTGRES_GID:-1000}
  USER_NAME=${USER:-postgresuser}
  DB_GROUP_NAME=${GROUP_NAME:-postgresusers}

  export USER_NAME=${USER_NAME}
  export DB_GROUP_NAME=${DB_GROUP_NAME}

  # Add group
  if [ ! $(getent group "${DB_GROUP_NAME}") ]; then
    groupadd -r "${DB_GROUP_NAME}" -g "${GROUP_ID}"
  fi

  # Add user to system
  if id "${USER_NAME}" &>/dev/null; then
      echo ' skipping user creation'
  else
      useradd -l -m -d /home/"${USER_NAME}"/ -u "${USER_ID}" --gid "${GROUP_ID}" -s /bin/bash -G "${DB_GROUP_NAME}" "${USER_NAME}"
  fi

fi

if [[ ${RUN_AS_ROOT} =~ [Tt][Rr][Uu][Ee] ]]; then
  user="root"
  group="root"
  cron_tab_command="crontab /backup-scripts/backups-cron"
  cron_command="cron -f"
else
  user="${USER_NAME}"
  group="${DB_GROUP_NAME}"
  cron_tab_command="crontab -u ${user} /backup-scripts/backups-cron"
  cron_command="gosu ${USER_NAME} cron -f"
fi

non_root_permission "${user}" "${group}"

if [[ ${RUN_ONCE} =~ [Tt][Rr][Uu][Ee] ]]; then
  /backup-scripts/backups.sh
else
  chmod gu+rw /var/run
  chmod gu+s /usr/sbin/cron
  ${cron_tab_command}
  ${cron_command}
fi
