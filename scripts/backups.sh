#!/bin/bash

source /backup-scripts/pgenv.sh

# Env variables
MYDATE=$(date +%d-%B-%Y-%H-%M)
MONTH=$(date +%B)
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
  CONSOLIDATE_AFTER_DAYS="$3"

  if s3cmd ls s3://${S3_BUCKET} 2>&1 | grep -q 'NoSuchBucket'; then
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

    # Handle sub-daily backup consolidation for files older than CONSOLIDATE_AFTER_DAYS
    CONSOLIDATE_AFTER=$(echo "$CONSOLIDATE_AFTER_DAYS" | awk '{print $1}')
    if [[ ${CONSOLIDATE_AFTER} -gt 0 ]]; then
      echo "Consolidating S3 backups older than ${CONSOLIDATE_AFTER_DAYS} (keeping 1 backup per day)" >> ${CONSOLE_LOGGING_OUTPUT}

      # Find all backup files older than CONSOLIDATE_AFTER days (excluding globals.sql)
      # Group by database + creation date (YYYY-MM-DD), keep earliest per day
      declare -A files_by_db_date
      while IFS= read -r line; do
        createDate=$(echo $line | awk {'print $1'})
        fileName=$(echo $line | awk {'print $4'})

        # Skip globals.sql and non-backup files
        if [[ "$fileName" == *"globals.sql"* ]] || [[ ! "$fileName" =~ \.(dmp|sql)(\.gz)? ]]; then
          continue
        fi

        createDateSeconds=$(date -d"$createDate" +%s)
        olderThanConsolidate=$(date -d"${CONSOLIDATE_AFTER_DAYS} ago" +%s)

        if [[ $createDateSeconds -lt $olderThanConsolidate ]]; then
          # Extract DB and date part from filename (everything before time portion)
          # Format: {DUMPPREFIX}_{DB}.{DD-Month-YYYY-HH-MM}.dmp.gz
          filename=$(basename "$fileName")
          db_date_key=$(echo "$filename" | sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\).*/\1/p')

          if [[ -n "$db_date_key" ]]; then
            # Keep the first file encountered for each database+date (since sorted chronologically, this is the earliest)
            if [[ -z "${files_by_db_date[$db_date_key]}" ]]; then
              files_by_db_date["$db_date_key"]="$createDateSeconds $fileName"
            fi
          fi
        fi
      done < <(s3cmd ls s3://${S3_BUCKET} --recursive 2>/dev/null | sort -k1,2)

      # Delete all files except the one we're keeping per database+date
      while IFS= read -r line; do
        createDate=$(echo $line | awk {'print $1'})
        fileName=$(echo $line | awk {'print $4'})

        # Skip globals.sql and non-backup files
        if [[ "$fileName" == *"globals.sql"* ]] || [[ ! "$fileName" =~ \.(dmp|sql)(\.gz)? ]]; then
          continue
        fi

        createDateSeconds=$(date -d"$createDate" +%s)
        olderThanConsolidate=$(date -d"${CONSOLIDATE_AFTER_DAYS} ago" +%s)

        if [[ $createDateSeconds -lt $olderThanConsolidate ]]; then
          # Extract DB and date part from filename (everything before time portion)
          # Format: {DUMPPREFIX}_{DB}.{DD-Month-YYYY-HH-MM}.dmp.gz
          filename=$(basename "$fileName")
          db_date_key=$(echo "$filename" | sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\).*/\1/p')

          if [[ -n "$db_date_key" ]] && [[ -n "${files_by_db_date[$db_date_key]:-}" ]]; then
            kept_file=$(echo "${files_by_db_date[$db_date_key]}" | awk '{print $2}')
            if [[ -n "$kept_file" ]] && [[ "$fileName" != "$kept_file" ]]; then
              echo "Deleting S3 backup: $fileName (keeping only one per day per database)" >> ${CONSOLE_LOGGING_OUTPUT}
              s3cmd del "$fileName"
            fi
          fi
        fi
      done < <(s3cmd ls s3://${S3_BUCKET} --recursive 2>/dev/null | sort -k1,2)
    fi
  fi
}

function dump_tables() {

    DATABASE=$1

    # Retrieve table names
    array=($(PGPASSWORD=${POSTGRES_PASS} psql ${PG_CONN_PARAMETERS} -d ${DATABASE} -At -F '.' -c "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'topology') AND table_name NOT IN ('raster_columns', 'raster_overviews', 'spatial_ref_sys', 'geography_columns', 'geometry_columns') ORDER BY table_schema, table_name;"))

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

        export PGPASSWORD=${POSTGRES_PASS}

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
      export FILENAME=${MYBACKUPDIR}/${DUMPPREFIX}_${DB}.${MYDATE}.dmp
    else
      export FILENAME=${MYBASEDIR}/"${ARCHIVE_FILENAME}.${DB}.dmp"
    fi

    if [[ "${DB_TABLES}" =~ [Ff][Aa][Ll][Ss][Ee] ]]; then
      export PGPASSWORD=${POSTGRES_PASS}
      echo -e "Backup  of \e[1;31m ${DB} \033[0m starting at \e[1;31m $(date) \033[0m" >> ${CONSOLE_LOGGING_OUTPUT}
      if [[ "${DB_DUMP_ENCRYPTION}" =~ [Tt][Rr][Uu][Ee] ]]; then
        if ! ( set -o pipefail && pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d "${DB}" | openssl enc -aes-256-cbc -pass pass:"${DB_DUMP_ENCRYPTION_PASS_PHRASE}" -pbkdf2 -iter 10000 -md sha256 -out "${FILENAME}" ); then
          echo -e "\e[1;31mFailed to back up ${DB} at $(date)\033[0m" >> ${CONSOLE_LOGGING_OUTPUT}
          rm ${FILENAME}
          continue
        fi
      else
        if ! pg_dump ${PG_CONN_PARAMETERS} ${DUMP_ARGS} -d ${DB} > ${FILENAME}; then
          echo -e "\e[1;31mFailed to back up ${DB} at $(date)\033[0m" >> ${CONSOLE_LOGGING_OUTPUT}
          rm ${FILENAME}
          continue
        fi
      fi
      echo -e "Backup of \e[1;33m ${DB} \033[0m completed at \e[1;33m $(date) \033[0m and dump located at \e[1;33m ${FILENAME} \033[0m" >> ${CONSOLE_LOGGING_OUTPUT}
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

function remove_files() {
  TIME_MINUTES=$((REMOVE_BEFORE * 24 * 60))
  MIN_SAVED_FILE=${MIN_SAVED_FILE:-0}
  CONSOLIDATE_AFTER=${CONSOLIDATE_AFTER:-0}
  CONSOLIDATE_AFTER_MINUTES=$((CONSOLIDATE_AFTER * 24 * 60))

  echo "Cleaning backups older than ${REMOVE_BEFORE} days (keeping at least ${MIN_SAVED_FILE})" >> ${CONSOLE_LOGGING_OUTPUT}

  # Handle sub-daily backup consolidation: keep only 1 backup per day for files older than CONSOLIDATE_AFTER days
  if [[ ${CONSOLIDATE_AFTER} -gt 0 ]]; then
    echo "Consolidating backups older than ${CONSOLIDATE_AFTER} days (keeping 1 backup per day)" >> ${CONSOLE_LOGGING_OUTPUT}

    # Find all backup files older than CONSOLIDATE_AFTER days (excluding globals.sql)
    # Format: timestamp filepath (sorted by time, oldest first to keep the first of the day)
    mapfile -t old_frequent_files_with_time < <(find "${MYBASEDIR}" -type f -mmin +${CONSOLIDATE_AFTER_MINUTES} -name "*.dmp*" ! -name "globals.sql" -printf "%T@ %p\n" | sort -n)

    # Group files by database and date (DD-Month-YYYY) and keep only the first one per day per database
    declare -A files_by_db_date
    for entry in "${old_frequent_files_with_time[@]}"; do
      timestamp=$(echo "$entry" | cut -d' ' -f1)
      file=$(echo "$entry" | cut -d' ' -f2-)
      filename=$(basename "$file")
      # Extract DB and date part from filename (everything before time portion)
      # Format 1: DUMPPREFIX_DB.DD-Month-YYYY-HH-MM.dmp (database backups)
      # Format 2: DUMPPREFIX_SCHEMA.TABLE_DD-Month-YYYY-HH-MM.dmp (table backups)
      db_date_key=$(echo "$filename" | sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\).*/\1/p')

      if [[ -n "$db_date_key" ]]; then
        # Keep the first file encountered for each database+date (since sorted chronologically, this is the earliest)
        if [[ -z "${files_by_db_date[$db_date_key]}" ]]; then
          files_by_db_date["$db_date_key"]="$timestamp $file"
        fi
      fi
    done

    # Delete all files except the one we're keeping per database+date
    for entry in "${old_frequent_files_with_time[@]}"; do
      file=$(echo "$entry" | cut -d' ' -f2-)
      filename=$(basename "$file")
      # Extract DB and date part from filename (everything before time portion)
      db_date_key=$(echo "$filename" | sed -n 's/\(.*\)-[0-9]\{2\}-[0-9]\{2\}\.\(dmp\|sql\).*/\1/p')

      if [[ -n "$db_date_key" ]] && [[ -n "${files_by_db_date[$db_date_key]:-}" ]]; then
        kept_file=$(echo "${files_by_db_date[$db_date_key]}" | cut -d' ' -f2-)
        if [[ -n "$kept_file" ]] && [[ "$file" != "$kept_file" ]]; then
          echo "Deleting backup: $file (keeping only one per day per database)" >> ${CONSOLE_LOGGING_OUTPUT}
          rm -f "$file"
        fi
      fi
    done
  fi

  # List all files and all files that are too old
  mapfile -t all_files < <(find "${MYBASEDIR}" -type f -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
  mapfile -t old_files < <(find "${MYBASEDIR}" -type f -mmin +${TIME_MINUTES} -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-)
  #We need to substract globals.sql
  number_of_files=$(( ${#all_files[@]} - 1 ))
  keep_count=$(( number_of_files < MIN_SAVED_FILE ? ${#all_files[@]} : MIN_SAVED_FILE ))
  max_deletable=$(( number_of_files - keep_count ))
  deletable=()
  i=0
  while [[ $i -lt $max_deletable && $i -lt ${#old_files[@]} ]]; do
    deletable+=("${old_files[$i]}")
    ((i++))
  done

  for f in "${deletable[@]}"; do
    echo "Deleting $f"
    rm -f "$f"
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
  PGPASSWORD=${POSTGRES_PASS} pg_dumpall ${PG_CONN_PARAMETERS}  --globals-only | s3cmd put - s3://${BUCKET}/globals.sql
  echo "Sync globals.sql to ${BUCKET} bucket  " >> ${CONSOLE_LOGGING_OUTPUT}
  backup_db "s3cmd sync -r ${MYBASEDIR}/* s3://${BUCKET}/"

elif [[ ${STORAGE_BACKEND} =~ [Ff][Ii][Ll][Ee] ]]; then
  # Backup globals Always get the latest
  PGPASSWORD=${POSTGRES_PASS} pg_dumpall ${PG_CONN_PARAMETERS}  --globals-only -f ${MYBASEDIR}/globals.sql
  # Loop through each pg database backing it up
  backup_db ""

fi


if [ "${REMOVE_BEFORE:-}" ]; then
  if [[ ${STORAGE_BACKEND} == "FILE" ]]; then
    remove_files
  elif [[ ${STORAGE_BACKEND} == "S3" ]]; then
    # Credits https://shout.setfive.com/2011/12/05/deleting-files-older-than-specified-time-with-s3cmd-and-bash/
    clean_s3bucket "${BUCKET}" "${REMOVE_BEFORE} days" "${CONSOLIDATE_AFTER:-0} days"
  fi
fi
