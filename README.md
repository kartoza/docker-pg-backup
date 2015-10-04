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
docker pull kartoza/pg-backup:9.4
docker pull kartoza/pg-backup:9.3
```

We highly suggest that you use a tagged image (9.4 or 9.3 currently available) as 
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

# Specifying environment


You can also use the following environment variables to pass a 
user name and password etc for the database connection.

## Database specific variables

* PGUSER if not set, defaults to : docker
* PGPASSWORD if not set, defaults to : docker
* PGPORT if not set, defaults to : 5432
* PGHOST if not set, defaults to : db
* PGDATABASE if not set, defaults to : gis
* DAILY number of daily backups to keep, defaults to : 7
* MONTHLY number of monthly backups to keep, defaults to : 12
* YEARLY number of yearly backups to keep, defaults to : 3

Daily, Monthly and Yearly environment variables are used to specify the 
frequency of backups to keep. For example, 7 Daily backups means the service
will keep 7 latest daily backups. 12 Monthly backups means the service will keep
12 latest monthly backups, with each backup is created at the first date each 
month. Similarly, yearly backup is created at 1st January each year.

## Remote backup connection variables

### SFTP

* USE_SFTP_BACKUP defaults to False. If set, it means the service will try to
  push the backup files to a remote sftp server
* SFTP_HOST should be set to IP address or domain name of SFTP server
* SFTP_USER should be set to relevant SFTP user
* SFTP_PASSWORD should be set to relevant SFTP password
* SFTP_DIR should be set to the default working directory that the backup will
  be stored into (in the SFTP server)

Example usage:

```
docker run -e PGUSER=bob -e PGPASSWORD=secret -link db -i -d kartoza/pg-backup
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

dbbackups:
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
    - PGUSER=docker
    - PGPASSWORD=docker
    - PGPORT=5432
    - PGHOST=db
    - PGDATABASE=gis  
```

Then run using:

```
docker-compose up -d dbbackup
```

# Remote backup connection

Sometimes we need to mirrors our local backup to another backup server. For
now, the means is supported via SFTP connection. By specifying SFTP related
environment variables, pg-backup will try to copy new backup to specified
remote server and cleanup unnecessary backup files in remote server (if it is
deleted in local backup server). The service will try to make backup files
synchronized between servers.

At some times, we may want to manually force each server to resync the files.
We wrapped two additional simple commands in start.sh script:

* Push to remote SFTP. Push all local backup files to specified remote SFTP
server. If there are any conflicting backup files in remote,
it will be overwritten.
* Pull from remote SFTP. Pull all remote backup files to local directory.
Similarly if there are any conflicting local backup files, it will be
overwritten.

## Executing the command

You can directly execute the command using docker exec or run because the
command is received in start.sh script. For example, if you already have a
pg-backup container running named pg-backup:

```
docker exec pg-backup /bin/sh -c "/start.sh push-to-remote-sftp"
```

The above command will push all local backup files in existing container
to remote sftp server.

# Credits

Tim Sutton (tim@kartoza.com)
April 2015

Rizky Maulana Nugraha (lana.pcfre@gmail.com)
October 2015
