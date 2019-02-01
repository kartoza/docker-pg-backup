FROM kartoza/postgis:11.0-2.5
MAINTAINER tim@kartoza.com
 
RUN apt-get install -y postgresql-client
ADD backups-cron /etc/cron.d/backups-cron
RUN touch /var/log/cron.log
ADD backups.sh /backups.sh
ADD start.sh /start.sh
 
CMD ["/start.sh"]
