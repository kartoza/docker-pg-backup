#!/bin/bash

source /backup-scripts/pgenv.sh

# Env variables
MYDATE=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%m)
YEAR=$(date +%Y)
MYBASEDIR=/${BUCKET}
MYBACKUPDIR=${MYBASEDIR}/${YEAR}/${MONTH}
mkdir -p ${MYBACKUPDIR}
pushd ${MYBACKUPDIR} || exit

function s3_config() {
  # If it doesn't exists, copy from ${EXTRA_CONF_DIR} directory if exists
  if [[ -f ${EXTRA_CONFIG_DIR}/s3cfg ]]; then
    cp -f ${EXTRA_CONFIG_DIR}/s3cfg /root/.s3cfg
  else
    # default value
    envsubst < /build_data/s3cfg > /root/.s3cfg
  fi


}

# Cleanup S3 bucket
function clean_s3bucket() {
  S3_BUCKET="$1"
  DEL_DAYS="$2"
  if [[ $(s3cmd ls s3://${BUCKET} 2>&1 | grep -q 'NoSuchBucket' ) ]];then
    echo "buckets empty , no cleaning needed"
  else
    s3cmd ls s3://${S3_BUCKET} --recursive | while read -r line; do
      createDate=$(echo $line | awk {'print $1'})
      createDate=$(date -d"$createDate" +%s)
      olderThan=$(date -d"$DEL_DAYS ago" +%s)
      if [[ $createDate -lt $olderThan ]]; then
        fileName=$(echo $line | awk {'print $4'})
        echo $fileName
        if [[ $fileName != "" ]]; then
          s3cmd del "$fileName"
        fi
      fi
    done
  fi
}

function dump_tables() {

    DATABASE=$1

    # Retrieve table names
    array=($(PGPASSWORD=${POSTGRES_PASSWORD} psql ${PG_CONN_PARAMETERS} -d ${DATABASE} -At -F '.' -c "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'topology') AND table_name NOT IN ('raster_columns', 'raster_overviews', 'spatial_ref_sys', 'geography_columns', 'geometry_columns') ORDER BY table_schema, table_name;"))

    for i in "${array[@]}"; do

        IFS='.' read -r -a strarr <<< "$i"
        SCHEMA_NAME="${strarr[0]}"
        TABLE_NAME="${strarr[1]}"

        # Combine schema and table name
        DB_TABLE="${SCHEMA_NAME}.${TABLE_NAME}"
        # Check dump format
        if [[ ${DUMP_ARGS} == '-Fc' ]]; then
            FORMAT='dmp'
        else
            FORMAT='sql'
        fi

        # Construct filename
        FILENAME="${DUMPPREFIX}_${DB_TABLE}_${MYDATE}.${FORMAT}"

        # Log the backup start time
        echo -e "Backup of \e[1;31m ${DB_TABLE} \033[0m from DATABASE \e[1;31m ${DATABASE} \033[0m starting at \e[1;31m $(date) \033[0m" >> ${CONSOLE_LOGGING_OUTPUT}

        export PGPASSWORD=${POSTGRES_PASSWORD}

        # Dump command
        if [[ "${DB_DUMP_ENCRYPTION}" =~ [Tt][Rr][Uu][Ee] ]]; then
            # Encrypted backup
            pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DATABASE}" -t "${DB_TABLE}" | openssl enc -aes-256-cbc -pass pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE} -pbkdf2 -iter 10000 -md sha256 -out "${FILENAME}"
            if [[ $? -ne 0 ]];then
             echo -e "Backup of \e[0;32m ${DB_TABLE} \033[0m from DATABASE \e[0;32m ${DATABASE} \033[0m failed" >> ${CONSOLE_LOGGING_OUTPUT}
            fi
        else
            # Plain backup
            pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DATABASE}" -t "${DB_TABLE}" > "${FILENAME}"
            if [[ $? -ne 0 ]];then
             echo -e "Backup of \e[0;32m ${DB_TABLE} \033[0m from DATABASE \e[0;32m ${DATABASE} \033[0m failed" >> ${CONSOLE_LOGGING_OUTPUT}
            fi
        fi

        # Log the backup completion time
        echo -e  "Backup of \e[1;33m ${DB_TABLE} \033[0m from DATABASE \e[1;33m ${DATABASE} \033[0m completed at \e[1;33m $(date) \033[0m" >> ${CONSOLE_LOGGING_OUTPUT}

    done
}


function backup_db() {
  EXTRA_PARAMS=''
  if [ -n "$1" ]; then
    EXTRA_PARAMS=$1
  fi
  for DB in ${DBLIST}; do
    if [ -z "${ARCHIVE_FILENAME:-}" ]; then
      export FILENAME=${MYBACKUPDIR}/${DB}_${MYDATE}.dmp
    else
      export FILENAME=${MYBACKUPDIR}/${DB}_"${ARCHIVE_FILENAME}.dmp"
    fi

    if [[ "${DB_TABLES}" =~ [Ff][Aa][Ll][Ss][Ee] ]]; then
      export PGPASSWORD=${POSTGRES_PASSWORD}
      echo -e "Backup  of \e[1;31m ${DB} \033[0m starting at \e[1;31m $(date) \033[0m" >> ${CONSOLE_LOGGING_OUTPUT}
      if [[ "${DB_DUMP_ENCRYPTION}" =~ [Tt][Rr][Uu][Ee] ]];then
        pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d ${DB} | openssl enc -aes-256-cbc -pass pass:${DB_DUMP_ENCRYPTION_PASS_PHRASE} -pbkdf2 -iter 10000 -md sha256 -out ${FILENAME}
      else
        pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d ${DB} > ${FILENAME}
      fi
      echo -e "Backup of \e[1;33m ${DB} \033[0m completed at \e[1;33m $(date) \033[0m and dump located at \e[1;33m ${FILENAME} \033[0m " >> ${CONSOLE_LOGGING_OUTPUT}
      if [[ ${STORAGE_BACKEND} == "S3" ]]; then
        gzip ${FILENAME}
        echo -e "Pushing database backup \e[1;31m ${FILENAME} \033[0m to \e[1;31m s3://${BUCKET}/ \033[0m" >> ${CONSOLE_LOGGING_OUTPUT}
        ${EXTRA_PARAMS}
        rm ${MYBACKUPDIR}/*.dmp.gz
      fi
    else

      dump_tables ${DB}
      if [[ ${STORAGE_BACKEND} == "S3" ]]; then
        ${EXTRA_PARAMS}
        rm ${MYBACKUPDIR}/*
      fi
    fi
  done

}


if [[ ${STORAGE_BACKEND} == "S3" ]]; then
  s3_config
  if s3cmd ls "s3://${BUCKET}" >/dev/null 2>&1; then
     echo "Bucket '${BUCKET}' exists."
  else
     echo "Bucket '${BUCKET}' does not exist. Creating..."
     s3cmd mb "s3://${BUCKET}"
  fi

  # Backup globals Always get the latest
  PGPASSWORD=${POSTGRES_PASSWORD} pg_dumpall ${PG_CONN_PARAMETERS}  --globals-only | s3cmd put - s3://${BUCKET}/globals.sql
  echo "Sync globals.sql to ${BUCKET} bucket  " >> ${CONSOLE_LOGGING_OUTPUT}
  backup_db "s3cmd sync -r ${MYBASEDIR}/* s3://${BUCKET}/"

elif [[ ${STORAGE_BACKEND} =~ [Ff][Ii][Ll][Ee] ]]; then
  # Backup globals Always get the latest
  PGPASSWORD=${POSTGRES_PASSWORD} pg_dumpall ${PG_CONN_PARAMETERS}  --globals-only -f ${MYBASEDIR}/globals.sql
  # Loop through each pg database backing it up
  backup_db ""

fi


if [ "${REMOVE_BEFORE:-}" ]; then
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))
  if [[ ${STORAGE_BACKEND} == "FILE" ]]; then
    echo "Removing following backups older than ${REMOVE_BEFORE} days" >> ${CONSOLE_LOGGING_OUTPUT}
    find ${MYBASEDIR}/* -type f -mmin +${TIME_MINUTES} -delete & >> ${CONSOLE_LOGGING_OUTPUT}
  elif [[ ${STORAGE_BACKEND} == "S3" ]]; then
    # Credits https://shout.setfive.com/2011/12/05/deleting-files-older-than-specified-time-with-s3cmd-and-bash/
    clean_s3bucket "${BUCKET}" "${REMOVE_BEFORE} days"
  fi
fi
