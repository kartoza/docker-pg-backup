#!/usr/bin/env bash

./build.sh

docker build -t kartoza/pg-backup:12.0 -f Dockerfile.test .
