# Docker PG Backup


A simple docker container that runs PostGIS backups. It is intended to be used
primarily with our [docker postgis](https://github.com/kartoza/docker-postgis)
docker image. By default it will create a backup once per night in a nicely
ordered directory by year / month.

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
docker run --name="backups" --hostname="pg-backups" -link db -i -d kartoza/pg-backups
```

# Specifying environment

**Note:** This is not implemented yet:

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


## Credits

Tim Sutton (tim@kartoza.com)
April 2015
