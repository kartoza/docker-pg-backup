#!/bin/bash

docker run --name="cron" --hostname="cron" -link watchkeeper_db_1 -i -d kartoza/pg-backups

