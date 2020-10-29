FROM kartoza/postgis:13.0
MAINTAINER tim@kartoza.com

RUN apt-get -y update; apt-get -y --no-install-recommends install  cron && apt-get -y --purge autoremove && apt-get clean \
&& rm -rf /var/lib/apt/lists/*
RUN touch /var/log/cron.log

ADD scripts /backup-scripts
RUN chmod 0755 /backup-scripts/*.sh

ENTRYPOINT ["/bin/bash", "/backup-scripts/start.sh"]
CMD ["/docker-entrypoint.sh"]


