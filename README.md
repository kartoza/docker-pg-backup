# Table of Contents
* [Docker PG Backup](#docker-pg-backup)
   * [Getting the image](#getting-the-image)
   * [Running the image](#running-the-image)
   * [Specifying environment variables](#specifying-environment-variables)
       * [Filename format](#filename-format)
   * [Backing up to S3 bucket](#backing-up-to-s3-bucket)
   * [Mounting Configs](#mounting-configs)
   * [Restoring](#restoring)
       * [Restore from file based backups](#restore-from-file-based-backups)
       * [Restoring from S3 bucket](#restoring-from-s3-bucket)
   * [Credits](#credits)
  
# Docker PG Backup

## Overview

* A docker container that runs PostgreSQL / PostGIS backups (PostGIS is not required it will backup any PG database). 
* It is primarily intended to be used with our [kartoza/postgis](https://github.com/kartoza/docker-postgis) docker image. 
* By default, it will create a backup once per night (at 23h00) in a nicely ordered directory by a year / month. 
* Environment variables to fine tune some backup parameters i.e.  
(e.g., hourly, every 30 minutes) using the `CRON_SCHEDULE` environment variable.
* Backup and restore to file or S3 environments (Tested with minio).
* Adapts all functionality from upstream [kartoza/postgis](https://github.com/kartoza/docker-postgis/)


## Getting the image

There are various ways to get the image onto your system:

### Pulling from Hub(Docker Hub)

```
docker pull kartoza/pg-backup:$POSTGRES_MAJOR_VERSION-$POSTGIS_MAJOR_VERSION.${POSTGIS_MINOR_RELEASE}
```

Where the environment variables are
```
POSTGRES_MAJOR_VERSION=18
POSTGIS_MAJOR_VERSION=3
POSTGIS_MINOR_RELEASE=6 
```

We highly suggest that you use a tagged image that match the PostgreSQL image you are running i.e
(kartoza/pg-backup:18-3.6 for backing up kartoza/postgis:18-3.6 DB). The
latest tag  may change and may not successfully back up your database. 

### Building the image locally


```
git clone https://github.com/kartoza/docker-pg-backup.git
cd docker-pg-backup
./build.sh 
```

## Running Services using the Image


To create a running container do:

### Use docker-compose

1) Make sure you have an env file with the following environmental
   variables set.
    
      ```bash
    POSTGRES_MAJOR_VERSION=18
    POSTGIS_MAJOR_VERSION=3
    POSTGIS_MINOR_RELEASE=5
    ```
   
2) Spin up the docker containers using the docker compose version installed on your machine i.e.
    ```bash
    docker-compose up -d or docker compose up -d
    ```

## Specifying environment variables

For a full description of the environment variables available with
this image look into [docker-env.md](https://github.com/kartoza/docker-pg-backup/blame/master/docker-env.md)


### Filename format

The default backup archive generated will be stored in the `/backups` directory 
(inside the container):

```
/backups/$(date +%Y)/$(date +%B)/${DUMPPREFIX}_${DB}.$(date +%d-%B-%Y-%H-%M).dmp
```

As a concrete example, with `DUMPPREFIX=PG` and if your postgis has DB name `gis`.
The backup archive would be something like:

```
/backups/2019/February/PG_gis.17-February-2019-14-30.dmp
```

The filename includes hour and minute (`%H-%M`) to support sub-daily backups. When restoring, you can specify 
a date alone to restore the latest backup of that day, or include the time (e.g., `2023-03-24-14-30`) to restore 
a specific backup.

If you specify `ARCHIVE_FILENAME` instead (default value is empty). The
filename will be fixed according to this prefix.
Let's assume `ARCHIVE_FILENAME=latest`
The backup archive would be something like

```
/backups/latest.gis.dmp
```

#### Backup Format

1) The database defaults to back up using the custom format `-Fc`.
2) A secondary option is specified using `-Fd`, this will backup
the database into a directory format. This is further compressed
for easy storage and uploading to S3 backends

   
## Backing up to S3 bucket
The script uses [s3cmd](https://s3tools.org/s3cmd) for backing up files to S3 bucket.

For a minimal example use [docker-compose-s3.yml](https://github.com/kartoza/docker-pg-backup/blob/master/docker-compose-s3.yml) for a quick start.

## Mounting Configs

The image supports mounting the following configs:
* `s3cfg` when backing to `S3` backend
* backup-cron for any custom configuration you need to specify in the file.
* `backup_monitoring.sh` - For any custom monitoring state on database dump completion or failure 
i.e Add webhook/callback support for backup completion notifications 

An environment variable `${EXTRA_CONFIG_DIR}` controls the location of the folder.

If you need to mount [s3cfg](https://gist.github.com/greyhoundforty/a4a9d80a942d22a8a7bf838f7abbcab2) file. You can run the following:

```
-e ${EXTRA_CONFIG_DIR}=/settings
-v /data:/settings
```
Where `s3cfg` is located in `/data`

If you need to run i.e webhook you can implement your own custom hook logic
```
-e ${EXTRA_CONFIG_DIR}=/settings
-v /data:/settings
```

## Restoring

There are two ways to restore files based on the location of the backup files.

* Restore from file based backups.
* Restore from cloud based backups.

### Restore from file based backups

Set the following environment variables:

 * `TARGET_DB` The db name to restore
 * `WITH_POSTGIS` Kartoza specific, to generate POSTGIS extension along with the restore process
 * `TARGET_ARCHIVE` The full path of the archive to restore

**Note:** The restore script will exit if you try to restore into an existing 
`TARGET_DB`. 

It is generally a good practice to restore into an empty new database and then manually
drop and rename the databases. 

After setting up the environment variables in the docker-compose.yml
and running it, you can execute the restore by running:

 ```
 docker-compose exec dbbackups /backup-scripts/restore.sh
 ```

### Restoring from S3 bucket
The script uses [s3cmd](https://s3tools.org/s3cmd) for restoring files S3 bucket to a postgresql database.

To restore from S3 bucket, first you have to exec into your running container. You have to launch the /backup-scripts/restore.sh with two parameters:
- the first parameter is the target date (and optionally time) that you want to restore:
  - Date only: `"2023-03-24"` - will restore the latest backup of that day
  - Date and time: `"2023-03-24-14-30"` - will restore the backup from 14:30 on that day
- the second parameter is for the database name you want your backup to be restored: ex `"vaultdb"`


For more docker-compose examples of these implementations look into the 
scenario_tests folder.

## Credits

Tim Sutton (tim@kartoza.com)

Admire Nyakudya (addloe@gmail.com)

Rizky Maulana 
