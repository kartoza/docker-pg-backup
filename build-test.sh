#!/usr/bin/env bash

./build.sh

docker build -t kartoza/pg-backup:manual-build -f Dockerfile.test .
