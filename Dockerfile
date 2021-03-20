FROM kartoza/postgis:13-3.1
MAINTAINER tim@kartoza.com


RUN apt-get -y update; apt-get -y --no-install-recommends install  cron python3-pip gettext  \
    && apt-get -y --purge autoremove && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install s3cmd
RUN touch /var/log/cron.log
ENV \
    STORAGE_BACKEND="FILE" \
    ACCESS_KEY_ID= \
    SECRET_ACCESS_KEY= \
    DEFAULT_REGION=us-west-2 \
    BUCKET=backups \
    HOST_BASE= \
    HOST_BUCKET= \
    SSL_SECURE=True \
    DUMP_ARGS="-Fc" \
    RESTORE_ARGS="-j 4" \
    CRON_SCHEDULE="0 23 * * *"


ADD scripts /backup-scripts
ADD s3cfg /settings/s3cfg.default
ADD backups-cron /settings/backups-cron.default
RUN chmod 0755 /backup-scripts/*.sh

ENTRYPOINT ["/bin/bash", "/backup-scripts/start.sh"]
CMD ["/scripts/docker-entrypoint.sh"]


