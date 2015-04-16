# Docker PG Backup


A simple docker container that runs PostGIS backups. It is intended to be used
primarily with our [docker postgis](https://github.com/kartoza/docker-postgis)
docker image. By default it will create a backup once per night (at 23h00)in a 
nicely ordered directory by year / month.

Visit our page on the docker hub at: https://github.com/kartoza/docker-pg-backup


## Getting the image

There are various ways to get the image onto your system:


The preferred way (but using most bandwidth for the initial image) is to
get our docker trusted build like this:


```
docker pull kartoza/pg-backup
```

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
           -i -d kartoza/pg-backups```
           
In this example I used a volume into which the actual backups will be
stored.

# Specifying environment


You can also use the following environment variables to pass a 
user name and password etc for the database connection.

Variable | Expected | Default if not specified
---------|----------|--------------------------
PGUSER | <user> | docker
PGPASSWORD | <password> | docker
PGPORT | <port> | 5432
PGHOST | <hostname / ip> | db
PGDATABASE | <database name> | gis

Example usage:

```
docker run -e PGUSER=bob -e PGPASSWORD=secret -link db -i -d kartoza/pg-backups
```

One other environment variable you may like to set is a prefix for the 
database dumps.


Variable | Expected | Default if not specified
---------|----------|--------------------------
DUMPPREFIX | <text> | PG_

Example usage:

```
docker run -e DUMPPREFIX=foo -link db -i -d kartoza/pg-backups
```



## Credits

Tim Sutton (tim@kartoza.com)
April 2015
