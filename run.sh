#!/bin/bash

docker run --name="backups"\
           --hostname="pg-backups" \
           --link=watchkeeper_db_1:db \
           -v /Users/timlinux/backups:/backups \
           -i -d kartoza/pg-backups

