#!/bin/bash
DEFAULT_EXTRA_CONF_DIR="/settings"


########################################
# Helpers
########################################
file_env() {
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

env_default() {
  local var="$1"
  local default="$2"

  if [[ -z "${!var:-}" ]]; then
    export "${var}=${default}"
  fi
}

########################################
# Core defaults
########################################
env_default RUN_AS_ROOT true
env_default EXTRA_CONF_DIR "${DEFAULT_EXTRA_CONF_DIR}"
env_default STORAGE_BACKEND FILE

########################################
# Secrets / file-backed vars
########################################
file_env ACCESS_KEY_ID
env_default ACCESS_KEY_ID ""

file_env DEFAULT_REGION
env_default DEFAULT_REGION us-west-2

file_env BUCKET
env_default BUCKET backups

########################################
# Connection / storage
########################################
file_env HOST_BASE
env_default HOST_BASE ""

env_default HOST_BUCKET ""
env_default SSL_SECURE True

env_default DUMP_ARGS "-Fc"
env_default RESTORE_ARGS "-j 4"

########################################
# Postgres credentials
########################################
file_env POSTGRES_USER
env_default POSTGRES_USER docker


env_default POSTGRES_PORT 5432
env_default POSTGRES_HOST db

########################################
# Naming / retention
########################################
env_default DUMPPREFIX PG
env_default ARCHIVE_FILENAME ""

env_default REMOVE_BEFORE ""
env_default CONSOLIDATE_AFTER ""

########################################
# Derived values (must come AFTER deps)
########################################
env_default PG_CONN_PARAMETERS "-h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER}"

########################################
# Runtime flags
########################################
env_default RUN_ONCE FALSE
env_default DB_DUMP_ENCRYPTION FALSE
env_default DB_TABLES FALSE
env_default CLEANUP_DRY_RUN false
env_default CHECKSUM_VALIDATION false
env_default S3_RETAIN_LOCAL_DUMPS false
env_default CONSOLE_LOGGING true
env_default JSON_LOGGING false

########################################
# Time calculations
########################################
env_default TIME_MINUTES "$((REMOVE_BEFORE * 24 * 60))"
env_default MIN_SAVED_FILE 0
env_default CONSOLIDATE_AFTER 0
env_default CONSOLIDATE_AFTER_MINUTES "$((CONSOLIDATE_AFTER * 24 * 60))"

########################################
# Restore / monitoring
########################################
env_default TARGET_ARCHIVE_DATETIME ""
env_default TARGET_ARCHIVE_DATE_ONLY ""
env_default MONITORING_ENDPOINT_COMMAND ""
env_default ENTRYPOINT_START backup


########################################
# Cron setting
########################################
build_cron() {
  cat > /backup-scripts/backups-cron <<EOF
${CRON_SCHEDULE} /bin/bash /backup-scripts/backups.sh

EOF
}


function cron_config() {
  if [[ -f "${EXTRA_CONF_DIR}/backups-cron" ]]; then
    envsubst < "${EXTRA_CONF_DIR}/backups-cron" > /backup-scripts/backups-cron
  else
    if [[ -z "${CRON_SCHEDULE}" ]]; then
      export CRON_SCHEDULE='0 23 * * *'
    fi

    build_cron
  fi
}

########################################
# File Permissions
########################################
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
  services=("${EXTRA_CONF_DIR}" "/build_data" "/root/" "/backups" "/etc" "/var/log" "/var/run/" "/usr/lib" "/usr/bin/")
  for paths in "${services[@]}"; do
    directory_checker "${paths}"
  done
}

mkdir -p ${EXTRA_CONF_DIR}

configure_env_variables() {
  # Vars that should be quoted (strings, secrets, paths)
  local quoted_vars=(
    PATH EXTRA_CONF_DIR STORAGE_BACKEND ACCESS_KEY_ID
    DEFAULT_REGION BUCKET HOST_BASE HOST_BUCKET SSL_SECURE
    DUMP_ARGS RESTORE_ARGS POSTGRES_USER POSTGRES_HOST
    DUMPPREFIX ARCHIVE_FILENAME DB_DUMP_ENCRYPTION
    PG_CONN_PARAMETERS DB_TABLES  CLEANUP_DRY_RUN
    CHECKSUM_VALIDATION CONSOLE_LOGGING MONITORING_ENDPOINT_COMMAND ENTRYPOINT_START JSON_LOGGING
  )

  # Vars that should be unquoted (numeric values)
  local unquoted_vars=(
    POSTGRES_PORT REMOVE_BEFORE CONSOLIDATE_AFTER MIN_SAVED_FILE RUN_ONCE
    TIME_MINUTES CONSOLIDATE_AFTER_MINUTES
  )

  {
    for var in "${quoted_vars[@]}"; do
      printf 'export %s="%s"\n' "$var" "${!var}"
    done

    for var in "${unquoted_vars[@]}"; do
      printf 'export %s=%s\n' "$var" "${!var}"
    done
  } > /backup-scripts/pgenv.sh
}


# Gosu preparations
user_permissions(){

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
}


setup_cron_env() {
  if [[ ${RUN_AS_ROOT} =~ [Tt][Rr][Uu][Ee] ]]; then
    user="root"
    group="root"
    cron_tab_command="crontab /backup-scripts/backups-cron"
    cron_command="cron -f"
  else
    user="${USER_NAME}"
    group="${DB_GROUP_NAME}"
    cron_tab_command="crontab -u ${user} /backup-scripts/backups-cron"
    cron_command="gosu ${user} cron -f"
  fi
}

run_backup() {
  non_root_permission "${user}" "${group}"

  if [[ ${RUN_ONCE} =~ [Tt][Rr][Uu][Ee] ]]; then
    echo -e "\e[32m ------------------------------------------------- \033[0m"
    echo -e "\e[32m [Entrypoint] Run backup script as a once off job. \033[0m"
    echo -e "\e[32m [Entrypoint] If CONSOLE_LOGGING=True, logs appear in Docker output else the logs are written to file. \033[0m"
    /backup-scripts/backups.sh
  else
    echo -e "\e[32m ----------------------------------------------------------- \033[0m"
    echo -e "\e[32m [Entrypoint] Run backup script as a cron job in foreground. \033[0m"
    echo -e "\e[32m [Entrypoint] If CONSOLE_LOGGING=True, logs appear in Docker output else the logs are written to file. \033[0m"
    chmod gu+rw /var/run
    chmod gu+s /usr/sbin/cron
    eval "${cron_tab_command}"
    eval "${cron_command}"
  fi
}


run_restore() {
  echo -e "\e[32m ------------------------------- \033[0m"
  echo -e "\e[32m [Entrypoint] Run restore logic. \033[0m"
  exec /backup-scripts/restore.sh
}

run_shell() {
  echo -e "\e[32m ------------------------------- \033[0m"
  echo -e "\e[32m [Entrypoint] Run shell.          \033[0m"
  exec /bin/bash
}


# Main Entrypoint
cron_config
configure_env_variables
user_permissions
setup_cron_env


case "${ENTRYPOINT_START,,}" in
  backup)
    run_backup
    ;;
  restore)
    run_restore
    ;;
  shell)
    run_shell
    ;;
  *)
    echo -e "\e[32m ------------------------------------------------------------ \033[0m"
    echo -e "\e[32m [Entrypoint] Invalid ENTRYPOINT_START='${ENTRYPOINT_START}'. \033[0m"
    echo -e "\e[32m [Entrypoint] Valid values: backup | restore | shell., defaulting to backup \033[0m"
    ENTRYPOINT_START=backup
    ;;
esac
