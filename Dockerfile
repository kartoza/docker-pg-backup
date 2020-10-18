FROM kartoza/postgis:13.0
MAINTAINER tim@kartoza.com

RUN apt-get -y update; apt-get -y --no-install-recommends install cron
RUN touch /var/log/cron.log
ENV CRON_SCHEDULE="0 23 * * *"

ADD scripts /backup-scripts
RUN chmod 0755 /backup-scripts/*.sh

ENTRYPOINT ["/bin/bash", "/backup-scripts/start.sh"]
CMD ["/scripts/docker-entrypoint.sh"]


