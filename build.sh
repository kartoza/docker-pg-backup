#!/bin/bash
docker build -t kartoza/pg-backup:manual-build .
docker build -t kartoza/pg-backup:13.0 .
