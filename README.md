# Odoo Backup


A simple docker container that run Odoo backups covering both Odoo files and PostgreSQL db based on [docker-pg-backup](https://github.com/kartoza/docker-pg-backup).
It then copy the backup files on GoogleDrive using drive cli.

## Getting the image

There are various ways to get the image onto your system:

The preferred way (but using most bandwidth for the initial image) is to
get our docker trusted build like this:


```
docker pull martel/odoo-backup:latest
```


To build the image yourself without apt-cacher (also consumes more bandwidth
since deb packages need to be refetched each time you build) do:

```
docker build -t martel/odoo-backup .
```

If you do not wish to do a local checkout first then build directly from github.

```
git clone git://github.com/martel-innovate/odoo-backup
```

## Run


To create a running container do:

```
docker run --name="backups"\
           --hostname="pg-backups" \
           --link=watchkeeper_db_1:db \
           -v ${PWD}/backup:/backup \
           -v ${PWD}/credentials.json:/var/credentials.json \
           -i -d martel/pg-backup
```
           
In this example I used a volume into which the actual backups will be
stored.

# Specifying environment


You can also use the following environment variables to pass a 
user name and password etc for the database connection.


* PGUSER if not set, defaults to : docker
* PGPASSWORD if not set, defaults to : docker
* PGPORT if not set, defaults to : 5432
* PGHOST if not set, defaults to : db
* PGDATABASE if not set, defaults to : db
* ODOO_FILES if not set, defaults to : 1 (it will backup also files in /var/lib/odoo)
* DRIVE_DESTINATION if not set, defaults to : "" (no path, so it will not run a Drive backup)

Example usage:

```
docker run -e PGUSER=bob -e PGPASSWORD=secret -e ODOO_FILES=1
    -e DRIVE_DESTINATION=path -link db -i -d martel/pg-backup
```

One other environment variable you may like to set is a prefix for the 
database dumps.

* DUMPPREFIX if not set, defaults to : PG

Example usage:

```
docker run -e DUMPPREFIX=foo -link db -i -d martel/pg-backup
```

Here is a more typical example using docker-composer:

For ``docker-compose.yml``:

```
db:
  image: postgres:9.4
  environment:
    - POSTGRES_USER=docker
    - POSTGRES_PASS=docker

dbbackups:
  image: martel/pg-backup:latest
  hostname: pg-backups
  links:
    - db:db
  volumes:
    - ${PWD}/backup:/var/backup
    - ${PWD}/credentials.json:/var/credentials/credentials.json #TODO document how to create the file
  environment:
    - ODOO_FILES=0
    - DRIVE_DESTINATION=path
    - ODOO_FILES=0
    - DRIVE_DESTINATION=path
    - PGHOST=db
    - PGDB=db
    - PGUSER=docker
    - PGPASSWORD=docker
    - PGPORT=5432
```

Then run using:

```
docker-compose up -d dbbackup
```