FROM kartoza/postgis:13.0
MAINTAINER tim@kartoza.com

RUN apt-get -y update; apt-get -y --no-install-recommends install  cron s3cmd awscli \
    && apt-get -y --purge autoremove && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN touch /var/log/cron.log
ENV \
    STORAGE_BACKEND='FILE' \
    ACCESS_KEY_ID= \
    SECRET_ACCESS_KEY= \
    DEFAULT_REGION='us-west-2' \
    BUCKET='backups' \
    HOST_BASE= \
    HOST_BUCKET= \
    SSL_SECURE='True' \
    DUMP_ARGS='-Fc' \
    EXTRA_CONF=


ADD scripts /backup-scripts
RUN chmod 0755 /backup-scripts/*.sh

ENTRYPOINT ["/bin/bash", "/backup-scripts/start.sh"]
CMD ["/docker-entrypoint.sh"]


