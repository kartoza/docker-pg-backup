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
docker pull kartoza/pg-backup:${VERSION}
where VERSION=13.0 ie
```

We highly suggest that you use a tagged image that match the PostgreSQL image you are running i.e
(13.0 for backing up kartoza/postgis:13.0 DB). The
latest tag  may change and may not successfully back up your database. 


To build the image yourself without apt-cacher (also consumes more bandwidth
since deb packages need to be fetched each time you build) do:

```
git clone https://github.com/kartoza/docker-pg-backup.git
cd docker-pg-backup
./build.sh # It will build the latest version
```

## Run


To create a running container do:

```
docker run --name="backups" --hostname="pg-backups" --link db1:db -v backups:/backups -i -d kartoza/pg-backup:13.0
```

## Specifying environment variables


You can also use the following environment variables to pass a
username and password etc for the database connection.

* POSTGRES_USER if not set, defaults to : docker
* POSTGRES_PASS if not set, defaults to : docker
* POSTGRES_PORT if not set, defaults to : 5432
* POSTGRES_HOST if not set, defaults to : db
* POSTGRES_DBNAME if not set, defaults to : gis
* ARCHIVE_FILENAME you can use your specified filename format here, default to empty, which means it will use default filename format.
* DBLIST a space-separated list of databases to backup, e.g. `gis postgres`. Default is all databases.
* REMOVE_BEFORE remove all old backups older than specified amount of days, e.g. `30` would only keep backup files younger than 30 days. Default: no files are ever removed.
* DUMP_ARGS='-Fc' The default dump argument to generate compressed 
database dumps. You can change this to generate other formats ie 
plain SQL dumps.
* RESTORE_ARGS='-j 4' The restore command to run four parallel jobs. You can 
  specify other arguments based on official postgis_restore documentation.
* STORAGE_BACKEND='FILE' The default backend is to store the files on the
host machine. Alternate backend is the s3 bucket (.ie minio or amazon bucket)
* DB_TABLES=yes Indicates if you need to dump all the tables in a DB into separate dumps.
The default behaviour is not to show this so that the dumps are for the database.



Example usage:

```
docker run -e POSTGRES_USER=bob -e POSTGRES_PASS=secret -link db -i -d kartoza/pg-backup
```

One other environment variable you may like to set is a prefix for the
database dumps.

* DUMPPREFIX if not set, defaults to : PG


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
The script uses [s3cmd](https://s3tools.org/s3cmd) to backup files to S3 bucket.


* ACCESS_KEY_ID= Access key for the bucket
* SECRET_ACCESS_KEY= Secret Access key for the bucket
* DEFAULT_REGION='us-west-2'  
* HOST_BASE= 
* HOST_BUCKET= 
* SSL_SECURE='True' This determines if the S3 bucket is hosted with SSL site
* BUCKET=backups Indicates the bucket name that will be created.

You can also mount the s3cfg configuration file as 

```
-v ./data/s3cfg:/config/s3cfg
```


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
December 2020