#!/bin/bash

docker run --name="backups" --hostname="pg-backups" -link db -i -d kartoza/pg-backups

