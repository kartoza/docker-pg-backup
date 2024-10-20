##############################################################################
# Production Stage                                                           #
##############################################################################
ARG POSTGRES_MAJOR_VERSION=17
ARG POSTGIS_MAJOR_VERSION=3
ARG POSTGIS_MINOR_RELEASE=5

FROM kartoza/postgis:$POSTGRES_MAJOR_VERSION-$POSTGIS_MAJOR_VERSION.${POSTGIS_MINOR_RELEASE} AS postgis-backup-production

RUN apt-get -y update; apt-get -y --no-install-recommends install  cron python3-pip vim  gettext \
    && apt-get -y --purge autoremove && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install s3cmd python-magic --break-system-packages
RUN touch /var/log/cron.log

ENV \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ADD build_data /build_data
ADD scripts /backup-scripts
RUN chmod 0755 /backup-scripts/*.sh
RUN sed -i 's/PostGIS/PgBackup/' ~/.bashrc

WORKDIR /backup-scripts

ENTRYPOINT ["/bin/bash", "/backup-scripts/start.sh"]
CMD []


##############################################################################
# Testing Stage                                                           #
##############################################################################
FROM postgis-backup-production AS postgis-backup-test

COPY scenario_tests/utils/requirements.txt /lib/utils/requirements.txt

RUN set -eux \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get -y --no-install-recommends install python3-pip \
    && apt-get -y --purge autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install -r /lib/utils/requirements.txt --break-system-packages
