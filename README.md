# Docker PG Backup


A simple docker container that runs PostGIS backups. It is intended to be used
primarily with our [docker postgis](https://github.com/kartoza/docker-postgis)
docker image. By default it will create a backup once per night (at 23h00)in a 
nicely ordered directory by year / month.

* Visit our page on the docker hub at: https://registry.hub.docker.com/u/kartoza/pg-backup/
* Visit our page on github at: https://github.com/kartoza/docker-pg-backup


## Getting the image

There are various ways to get the image onto your system:


The preferred way (but using most bandwidth for the initial image) is to
get our docker trusted build like this:


```
docker pull kartoza/pg-backup:latest
docker pull kartoza/pg-backup:9.6
docker pull kartoza/pg-backup:9.5
docker pull kartoza/pg-backup:9.4
docker pull kartoza/pg-backup:9.3
```

We highly suggest that you use a tagged image (9.6 currently available) as 
latest may change and may not successfully back up your database. Use the same or 
greater version of postgis as the database you are backing up.


To build the image yourself without apt-cacher (also consumes more bandwidth
since deb packages need to be refetched each time you build) do:

```
docker build -t kartoza/pg-backups .
```

If you do not wish to do a local checkout first then build directly from github.

```
git clone git://github.com/kartoza/docker-postgis
```

## Run


To create a running container do:

```
docker run --name="backups"\
           --hostname="pg-backups" \
           --link=watchkeeper_db_1:db \
           -v backups:/backups \
           -i -d kartoza/pg-backup:9.4
```
           
In this example I used a volume into which the actual backups will be
stored.

## Specifying environment


You can also use the following environment variables to pass a 
user name and password etc for the database connection.

**Note:** These variable names were changed when updating to support our PG version 10 image so that the names used here are consistent with those used in the postgis v10 image.

* POSTGRES_USER if not set, defaults to : docker
* POSTGRES_PASS if not set, defaults to : docker
* POSTGRES_PORT if not set, defaults to : 5432
* POSTGRES_HOST if not set, defaults to : db
* POSTGRES_DBNAME if not set, defaults to : gis
* ARCHIVE_FILENAME you can use your specified filename format here, default to empty, which means it will use default filename format.

Example usage:

```
docker run -e POSTGRES_USER=bob -e POSTGRES_PASS=secret -link db -i -d kartoza/pg-backup
```

One other environment variable you may like to set is a prefix for the 
database dumps.

* DUMPPREFIX if not set, defaults to : PG

Example usage:

```
docker run -e DUMPPREFIX=foo -link db -i -d kartoza/pg-backup
```

Here is a more typical example using docker-composer (formerly known as fig):

For ``docker-compose.yml``:

```
db:
  image: kartoza/postgis:9.4-2.1
  volumes:
    - ./pg/postgres_data:/var/lib/postgresql
    - ./pg/setup_data:/home/setup
  environment:
    - USERNAME=docker
    - PASS=docker

dbbackup:
  image: kartoza/pg-backup:9.4
  hostname: pg-backups
  volumes:
    - ./backups:/backups
  links:
    - db:db
  environment:
    - DUMPPREFIX=PG_YOURSITE
    # These are all defaults anyway, but setting explicitly in
    # case we ever want to ever use different credentials
    - POSTGRES_USER=docker
    - POSTGRES_PASS=docker
    - POSTGRES_PORT=5432
    - POSTGRES_HOST=db
    - POSTGRES_DBNAME=gis  
```

Then run using:

```
docker-compose up -d dbbackup
```

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

## Restoring

A simple restore script is provided.
You need to specify some environment variables first:

 * TARGET_DB: the db name to restore
 * WITH_POSTGIS: Kartoza specific, to generate POSTGIS extension along with the restore process
 * TARGET_ARCHIVE: the full path of the archive to restore
 
 The restore script will delete the `TARGET_DB`, so make sure you know what you are doing.
 Then it will create a new one and restore the content from `TARGET_ARCHIVE`
 
 If you specify these environment variable using docker-compose.yml file, 
 then you can execute a restore process like this:
 
 ```
 docker-compose exec dbbackup /restore.sh
 ```

## Credits

Tim Sutton (tim@kartoza.com)
April 2015
