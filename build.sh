#!/usr/bin/env bash

if [[ ! -f .env ]]; then
    echo "Default build arguments don't exists. Creating one from default value."
    cp .example.env .env
fi

docker pull kartoza/postgis:$POSTGRES_MAJOR_VERSION-$POSTGIS_MAJOR_VERSION.${POSTGIS_MINOR_RELEASE}

if [[ $(dpkg -l | grep "docker-compose") > /dev/null ]];then

  docker-compose -f docker-compose.build.yml build postgis-backup-prod
else
  docker compose -f docker-compose.build.yml build postgis-backup-prod
fi