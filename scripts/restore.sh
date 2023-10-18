#!/bin/bash


#!/bin/bash

source /backup-scripts/pgenv.sh

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


function s3_restore() {
 if [[ ! $1 || "$(date -d "$1" +%Y-%m-%d 2> /dev/null)" = "$3" ]]; then
  		echo "invalid date"
  		exit 1
    else
		MYDATE=$(date -d "$1" +%d-%B-%Y)
		MONTH=$(date -d "$1" +%B)
		YEAR=$(date -d "$1" +%Y)
		MYBASEDIR=/${BUCKET}
		MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
		BACKUP_URL=${MYBACKUPDIR}/${DUMPPREFIX}_${2}.${MYDATE}.dmp.gz
		if [[ "$(s3cmd ls s3://${BACKUP_URL} | wc -l)" = 1 ]]; then 
			s3cmd get s3://${BACKUP_URL} /data/dump/$2.dmp.gz
    		gunzip /data/dump/$2.dmp.gz
			echo "delete target DB with if its exists and recreate it"
			PGPASSWORD=${POSTGRES_PASS} dropdb ${PG_CONN_PARAMETERS} --force --if-exists ${2}
			PGPASSWORD=${POSTGRES_PASS} createdb ${PG_CONN_PARAMETERS} -O ${POSTGRES_USER} ${2}
			 if [[ "${DB_DUMP_ENCRYPTION}" =~ [Tt][Rr][Uu][Ee] ]];then
			  openssl enc -d -aes-256-cbc -pass pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE} -pbkdf2 -iter 10000 -md sha256 -in /data/dump/$2.dmp -out /tmp/decrypted.dump.gz | PGPASSWORD=${POSTGRES_PASS} pg_restore ${PG_CONN_PARAMETERS} /tmp/decrypted.dump.gz  -d $2 ${RESTORE_ARGS}
			  rm -r /tmp/decrypted.dump.gz
			else
			  PGPASSWORD=${POSTGRES_PASS} pg_restore ${PG_CONN_PARAMETERS} /data/dump/$2.dmp  -d $2 ${RESTORE_ARGS}
			fi
		fi
	fi
}

function file_restore() {
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
	PGPASSWORD=${POSTGRES_PASS} dropdb ${PG_CONN_PARAMETERS} --if-exists ${TARGET_DB}


	if [ -z "${WITH_POSTGIS:-}" ]; then
		echo "Recreate target DB without POSTGIS"
		PGPASSWORD=${POSTGRES_PASS} createdb ${PG_CONN_PARAMETERS} -O ${POSTGRES_USER} ${TARGET_DB}
	else
		echo "Recreate target DB with POSTGIS"
		PGPASSWORD=${POSTGRES_PASS} createdb ${PG_CONN_PARAMETERS} -O ${POSTGRES_USER}  ${TARGET_DB}
		PGPASSWORD=${POSTGRES_PASS} psql ${PG_CONN_PARAMETERS} -c 'CREATE EXTENSION IF NOT EXISTS postgis;' ${TARGET_DB}
	fi

	echo "Restoring dump file"
	# Only works if the cluster is different- all the credentials are the same
	#psql -f /backups/globals.sql ${TARGET_DB}
	if [[ "${DB_DUMP_ENCRYPTION}" =~ [Tt][Rr][Uu][Ee] ]];then
	  openssl enc -d -aes-256-cbc -pass pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE} -pbkdf2 -iter 10000 -md sha256 -in ${TARGET_ARCHIVE} -out /tmp/decrypted.dump.gz | PGPASSWORD=${POSTGRES_PASS} pg_restore ${PG_CONN_PARAMETERS} /tmp/decrypted.dump.gz  -d ${TARGET_DB} ${RESTORE_ARGS}
	  rm /tmp/decrypted.dump.gz
	else
	  PGPASSWORD=${POSTGRES_PASS} pg_restore ${PG_CONN_PARAMETERS} ${TARGET_ARCHIVE}  -d ${TARGET_DB} ${RESTORE_ARGS}
	fi

}

if [[ ${STORAGE_BACKEND} == "S3" ]]; then
	s3_config
	s3_restore $1 $2
elif [[ ${STORAGE_BACKEND} =~ [Ff][Ii][Ll][Ee] ]]; then
	file_restore
fi
