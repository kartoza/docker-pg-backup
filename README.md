# Docker PG Backup


A simple docker container that runs PostgreSQL / PostGIS backups (PostGIS is not required it will backup any PG database). 
It is intended to be used primarily with our [docker postgis](https://github.com/kartoza/docker-postgis)
docker image. By default, it will create a backup once per night (at 23h00)in a
nicely ordered directory by a year / month.

* Visit our page on the docker hub at: https://registry.hub.docker.com/u/kartoza/pg-backup/
* Visit our page on github at: https://github.com/kartoza/docker-pg-backup


## Getting the image

There are various ways to get the image onto your system:


The preferred way (but using most bandwidth for the initial image) is to
get our docker trusted build like this:


```
docker pull kartoza/pg-backup:latest
docker pull kartoza/pg-backup:$POSTGRES_MAJOR_VERSION-$POSTGIS_MAJOR_VERSION.${POSTGIS_MINOR_RELEASE}
```

Where the environment variables are
```
POSTGRES_MAJOR_VERSION=13
POSTGIS_MAJOR_VERSION=3
POSTGIS_MINOR_RELEASE=1 
```

We highly suggest that you use a tagged image that match the PostgreSQL image you are running i.e
(kartoza/pg-backup:13-3.1 for backing up kartoza/postgis:13-3.1 DB). The
latest tag  may change and may not successfully back up your database. 


To build the image yourself do:

```
git clone https://github.com/kartoza/docker-pg-backup.git
cd docker-pg-backup
./build.sh # It will build the latest version
```

## Run


To create a running container do:

```
docker run --name "db"  -p 25432:5432 -d -t kartoza/postgis:13-3.1
docker run --name="backups"  --link db:db -v `pwd`/backups:/backups  -d kartoza/pg-backup:13-3.1
```

## Specifying environment variables


You can also use the following environment variables to pass a
username and password etc for the database connection.

* POSTGRES_USER if not set, defaults to : docker
* POSTGRES_PASS if not set, defaults to : docker
* POSTGRES_PORT if not set, defaults to : 5432
* POSTGRES_HOST if not set, defaults to : db
* ARCHIVE_FILENAME you can use your specified filename format here, default to empty, which means it will use default filename format.
* DBLIST a space-separated list of databases to backup, e.g. `gis,data`. Default is all databases.
* REMOVE_BEFORE remove all old backups older than specified amount of days, e.g. `30` would only keep backup files younger than 30 days. Default: no files are ever removed.
* DUMP_ARGS='-Fc' The default dump argument to generate compressed 
database dumps. You can change this to generate other formats ie plain SQL dumps.
* RESTORE_ARGS='-j 4' The restore command to run four parallel jobs. You can 
  specify other arguments based on official postgis_restore documentation.
* STORAGE_BACKEND='FILE' The default backend is to store the files on the
host machine. Alternate backend is the s3 bucket (.ie minio or amazon bucket)
* DB_TABLES=yes Indicates if you need to dump all the tables in a DB into separate dumps.
The default behaviour is not to show this so that the dumps are for the database.
  
* CRON_SCHEDULE specifies the cron schedule when the backup needs to run. Defaults to midnight daily.

**Note** To avoid interpolation issues with the env variable `${CRON_SCHEDULE}` you will
need to provide the variable as a quoted string i.e ${CRON_SCHEDULE}='*/1 * * * *' 
or ${CRON_SCHEDULE}="*/1 * * * *" 

Here is a more typical example using [docker-composer](https://github.com/kartoza/docker-pg-backup/blob/master/docker-compose.yml):


## Filename format

The default backup archive generated will be stored in this directory (inside the container):

```
/backups/$(date +%Y)/$(date +%B)/${DUMPPREFIX}_${DB}.$(date +%d-%B-%Y).dmp
```

As a concrete example, with `DUMPPREFIX=PG` and if your postgis has DB name `gis`.
The backup archive would be something like:

```
/backups/2019/February/PG_gis.13-February-2019.dmp
```

If you specify `ARCHIVE_FILENAME` instead (default value is empty). The
filename will be fixed according to this prefix.
Let's assume `ARCHIVE_FILENAME=/backups/latest`
The backup archive would be something like

```
/backups/latest.gis.dmp
```

# Backing up to S3 bucket
The script uses [s3cmd](https://s3tools.org/s3cmd) for backing up files to S3 bucket.


* ACCESS_KEY_ID= Access key for the bucket
* SECRET_ACCESS_KEY= Secret Access key for the bucket
* DEFAULT_REGION='us-west-2'  
* HOST_BASE= 
* HOST_BUCKET= 
* SSL_SECURE='True' This determines if the S3 bucket is hosted with SSL site
* BUCKET=backups Indicates the bucket name that will be created.

You can also mount the `s3cfg` or `backups-cron` configuration file as 

```
-e ${EXTRA_CONFIG_DIR}=/settings
-v /data:/settings
```
Where `s3cfg` is located in `/data`


For a typical usage of this look at the docker-compose-s3.yml
## Restoring

A simple restore script is provided.
You need to specify some environment variables first:

 * TARGET_DB: the db name to restore
 * WITH_POSTGIS: Kartoza specific, to generate POSTGIS extension along with the restore process
 * TARGET_ARCHIVE: the full path of the archive to restore

**NB:** The restore script will try to delete the `TARGET_DB` if it matches an existing database, 
so make sure you know what you are doing. 
Then it will create a new one and restore the content from `TARGET_ARCHIVE`

It is generally a good practice to restore into an empty new database and then manually
drop and rename the databases. i.e if your original database was called `gis` you can 
restore into a new database called `gis_restore`

 If you specify these environment variables using docker-compose.yml file,
 then you can execute a restore process like this:

 ```
 docker-compose exec dbbackup /backup-scripts/restore.sh
 ```

## Credits

Tim Sutton (tim@kartoza.com)
Admire Nyakudya (admire@kartoza.com)
Rizky Maulana (rizky@kartoza.com)
July 2021