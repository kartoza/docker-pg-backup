FROM kartoza/postgis:9.6-2.4
MAINTAINER tim@kartoza.com
 
RUN apt-get -y update; apt-get install -y postgresql-client
ADD backups-cron /etc/cron.d/backups-cron
RUN touch /var/log/cron.log
ADD backups.sh /backups.sh
ADD restore.sh /restore.sh
ADD start.sh /start.sh

ENTRYPOINT []
CMD ["/start.sh"]
