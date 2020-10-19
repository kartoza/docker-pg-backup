FROM kartoza/postgis:13.0
MAINTAINER tim@kartoza.com

RUN apt-get -y update; apt-get -y --no-install-recommends install cron awscli
RUN touch /var/log/cron.log
ENV \
    CRON_SCHEDULE='0 23 * * *' \
    AWS_CONFIG_LOCATION=/root/.aws \
    AWS_CONFIG_FILE=$AWS_CONFIG_LOCATION/config \
    STORAGE_BACKEND='FILE' \
    AWS_ACCESS_KEY_ID='' \
    AWS_SECRET_ACCESS_KEY='' \
    AWS_DEFAULT_REGION='us-west-2' \
    AWS_DEFAULT_OUTPUT='json' \
    S3_BUCKET='db_backups'

RUN mkdir ${AWS_CONFIG_LOCATION}
ADD scripts /backup-scripts
RUN chmod 0755 /backup-scripts/*.sh

ENTRYPOINT ["/bin/bash", "/backup-scripts/start.sh"]
CMD ["/scripts/docker-entrypoint.sh"]


