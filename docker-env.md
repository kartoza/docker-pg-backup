Below is a list of environment variables that can be used with the image.

# PostgreSQL Database

These environment variables are useful to configure PostgreSQL database.

* `POSTGRES_USER` defaults to : docker
* `POSTGRES_PASS` defaults to : docker
* `POSTGRES_PORT` defaults to : 5432
* `POSTGRES_HOST` defaults to : db

For more environment variables regarding the database consult [docker-postgis](https://github.com/kartoza/docker-postgis/)
or your choice of database if you are using a specific one.

# PostgreSQL Backup

These environment variables are useful to configure backup options.

* `ARCHIVE_FILENAME` you can use your specified filename format here, default to empty, which 
means it will use default filename format.
* `DBLIST` a space-separated list of databases for backup, e.g. `gis data`. Default is all 
databases.
* `REMOVE_BEFORE` remove all old backups older than specified amount of days, e.g. `30` would 
only keep backup files younger than 30 days. Default: no files are ever removed.
* `MIN_SAVED_FILE` if set, it ensures that we keep at least this amount of files. For instance, if we 
choose `20`, we will at least keep 20 backups even if they are older than `REMOVE_BEFORE`. Default: set to 0.
* `CONSOLIDATE_AFTER` after the specified number of days, consolidate sub-daily backups (e.g., hourly, every 30 minutes) 
to one backup per day. For example, `7` would keep all sub-daily backups for 7 days, then consolidate older ones to daily backups. 
Default: `0` (no consolidation, all sub-daily backups are kept).
* `DUMP_ARGS` The default dump arguments based on official 
  [PostgreSQL Dump options](https://www.postgresql.org/docs/18/app-pgdump.html).
* `RESTORE_ARGS` Additional restore commands based on official [PostgreSQL restore](https://www.postgresql.org/docs/18/app-pgrestore.html) 
* `STORAGE_BACKEND` The default backend is to store the backup files. It can either
  be `FILE` or `S3`(Example minio or amazon bucket) backends. 
* `DB_TABLES` A boolean variable to specify if the user wants to dump the DB as individual tables. 
  Defaults to `No`
* `CRON_SCHEDULE` specifies the cron schedule when the backup needs to run. Defaults to 
midnight daily.
* `DB_DUMP_ENCRYPTION` boolean value specifying if you need the backups to be encrypted.
* `RUN_ONCE` useful to run the container as a once off job and exit. Useful in Kubernetes context
* `MONITORING_ENDPOINT_COMMAND` Webhook command to run for monitoring success or failure of backups i.e. """curl -D - -X POST -G 'https://appsignal-endpoint.net/check_ins/heartbeats' -d 'api_key=YOUR-APP-LEVEL-API-KEY' -d 'identifier=YOUR-CHECK-IN-IDENTIFIER'"""

**Note** To avoid interpolation issues with the env variable `${CRON_SCHEDULE}` you will
need to provide the variable as a quoted string i.e ${CRON_SCHEDULE}='*/1 * * * *' 
or ${CRON_SCHEDULE}="*/1 * * * *" 

# S3 Specific Env variables
You need to specify the following environment variables backup to S3

* `ACCESS_KEY_ID` Access key for the bucket
* `SECRET_ACCESS_KEY` Secret Access key for the bucket
* `DEFAULT_REGION` Defaults to 'us-west-2'  
* `HOST_BASE`
* `HOST_BUCKET` 
* `SSL_SECURE` The determines if the S3 bucket is 
* `BUCKET` Indicates the bucket name that will be created.
