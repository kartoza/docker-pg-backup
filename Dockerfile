FROM kartoza/postgis:11.0-2.5
MAINTAINER tim@kartoza.com

RUN apt-get -y update; apt-get install -y postgresql-client
RUN touch /var/log/cron.log

COPY backups-cron /backups-cron
COPY backups.sh /backups.sh
COPY restore.sh /restore.sh
COPY start.sh /start.sh

ENTRYPOINT ["/bin/bash", "/start.sh"]
