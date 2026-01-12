# Table of Contents
- [Docker PG Backup](#docker-pg-backup)
  * [Overview](#overview)
  * [Getting the image](#getting-the-image)
    + [Pulling from Hub(Docker Hub)](#pulling-from-hub-docker-hub-)
    + [Building the image locally](#building-the-image-locally)
  * [Running Services using the Image](#running-services-using-the-image)
    + [Use docker-compose](#use-docker-compose)
  * [Configuring backup with environment variables](#configuring-backup-with-environment-variables)
    + [Filename format](#filename-format)
    + [Backup Format](#backup-format)
        * [Using Custom Format](#using-custom-format)
        * [Using Directory Format](#using-directory-format)
  * [Backup Location](#backup-location)
    + [Backing up to S3 bucket](#backing-up-to-s3-bucket)
  * [Mounting Configs](#mounting-configs)
  * [Restoring](#restoring)
    + [Restore using Archive](#restore-using-archive)
    + [Date Based Restore](#date-based-restore)
      - [Date](#date)
      - [DateTime](#datetime)
  * [Entrypoint](#entrypoint)
  * [Credits](#credits)
  
# Docker PG Backup

## Overview

* A docker container that runs PostgreSQL / PostGIS backups (PostGIS is not required it will backup any PG database). 
* It is primarily intended to be used with our [kartoza/postgis](https://github.com/kartoza/docker-postgis) docker image. 
* By default, it will create a backup once per night (at 23h00) in a nicely ordered directory by a year / month. 
* Environment variables to fine tune some backup parameters i.e.  
(e.g., hourly, every 30 minutes) using the `CRON_SCHEDULE` environment variable.
* Backup and restore to file or S3 environments (Tested with minio).


## Getting the image

There are various ways to get the image onto your system:

### Pulling from Hub(Docker Hub)

```
POSTGRES_MAJOR_VERSION=18
POSTGIS_MAJOR_VERSION=3
POSTGIS_MINOR_RELEASE=6 
docker pull kartoza/pg-backup:$POSTGRES_MAJOR_VERSION-$POSTGIS_MAJOR_VERSION.${POSTGIS_MINOR_RELEASE}
```

We highly suggest that you use a tagged image that match the PostgreSQL 
image you are running i.e. (kartoza/pg-backup:18-3.6 for backing up kartoza/postgis:18-3.6 DB).


### Building the image locally


```
git clone https://github.com/kartoza/docker-pg-backup.git
cd docker-pg-backup
./build.sh 
```

## Running Services using the Image


To create a running container do:

### Use docker-compose

1) Make sure you have an env file. Use the example given
    
      ```bash
    cp .example.env .env
    ```
   
2) Start the services using docker compose
    ```bash
    docker-compose up -d 
    ```

## Configuring backup with environment variables

For a full description of the environment variables available with
this image look into [docker-env.md](https://github.com/kartoza/docker-pg-backup/blame/master/docker-env.md)


### Filename format

The default backup archive generated will be stored in the `/backups` directory 
(inside the container):

```
/backups/$(date +%Y)/$(date +%B)/${DUMPPREFIX}_${DB}.$(date +%d-%B-%Y-%H-%M).dmp
```

As a concrete example, with `DUMPPREFIX=PG` and if your postgis has DB 
name `gis`. The backup archive would be something like:

```
/backups/2019/February/PG_gis.17-February-2019-14-30.dmp
```

The filename includes hour and minute (`%H-%M`) to support sub-daily backups.


If you specify `ARCHIVE_FILENAME` instead (default value is empty). The
filename will be fixed according to this prefix.
Let's assume `ARCHIVE_FILENAME=latest`. The backup archive would be something like

```
/backups/latest.gis.dmp
```

### Backup Format

You can use the env `DUMP_ARGS` to specify the dump format.
The image defaults to specifying the following:

##### Using Custom Format 
* `DUMP_ARGS=-Fc` Dumps a compressed archive of the database.

##### Using Directory Format 
* `DUMP_ARGS=-Fd` Dumps the database into a directory format. 

**Note:** For S3 backends, this is compressed into a tar archive.


   
## Backup Location
* Directory inside the container or docker volume.
or a directory mounted within the image. 
* S3 Backends - cloud storage i.e. Minio

### Backing up to S3 bucket
We currently use [s3cmd](https://s3tools.org/s3cmd) for backing up files to S3 bucket.

For a quick start use [docker-compose-s3.yml](https://github.com/kartoza/docker-pg-backup/blob/master/docker-compose-s3.yml) .

## Mounting Configs

The image supports mounting the following configs:
* `s3cfg` when backing to `S3` backend
* `backup-cron` for any custom configuration you need to specify in the file.
* `backup_monitoring.sh` For any custom monitoring state on database dump completion or failure.

If you need to mount [s3cfg](https://gist.github.com/greyhoundforty/a4a9d80a942d22a8a7bf838f7abbcab2) file. You can run the following:

```
-v /data:/settings
```
Where `s3cfg` is located in `/data`.


## Restoring

When the backend is S3, files are downloaded (`.gz` or `.dir.tar.gz`) locally and then
restore can happen into an empty database.


### Restore using Archive

Set the following environment variables:

 * `TARGET_DB` The db name to restore
 * `WITH_POSTGIS` Kartoza specific, to generate POSTGIS extension along with 
the restore process
 * `TARGET_ARCHIVE` The full path of the archive to restore.
 * `STORAGE_BACKEND` This will determine where the archive is fetched
from with either it being downloaded and processed (S3 backends)
or local file backups.

**Note:** The restore script will exit if you try to restore into an existing 
`TARGET_DB`. 

It is generally a good practice to restore into an empty new database and then manually
drop and rename the databases. 

After setting up the environment variables in the docker-compose.yml
and running it, you can execute the restore by running:

 ```
 docker-compose exec dbbackups /backup-scripts/restore.sh
 ```


###  Date Based Restore
You can restore a specific backup based on time or date
it was generated using the env

#### Date
* `TARGET_ARCHIVE_DATE`.

Example:

Date only: `"2023-03-24"` - will restore the latest backup of that day.

#### DateTime
* `TARGET_ARCHIVE_DATETIME`.
Date and time: `"2023-03-24-14-30"` - will restore the backup from 14:30 on that day

## Entrypoint
The image supports running multiple entrypoints. The following
are supported
1) backup - By default this will run the backup script either
as a cron job or a once off depending on the environment variable
configuration.
```bash
docker run -it -e ENTRYPOINT_START=backup kartoza/pg-backup:${TAG:-18-3.6}
```
2) restore - This will allow you to run the restore script without
executing into the container first.
```bash
docker run -it -e ENTRYPOINT_START=restore kartoza/pg-backup:${TAG:-18-3.6}
```
3) shell - This will allow you to execute into the container and run interactive
commands. This is just for testing purposes mainly.

**Note:** You are still required to pass other additional env 
params to allow you entrypoint command to be executed correctly
i.e. backup requires the DB params etc

## Credits

Tim Sutton (tim@kartoza.com)

Admire Nyakudya (addloe@gmail.com)

Rizky Maulana 
