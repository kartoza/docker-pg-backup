FROM kartoza/postgis:9.3-2.1
MAINTAINER tim@kartoza.com
 
RUN apt-get install -y postgresql-client
ADD backups-cron /etc/cron.d/backups-cron
RUN touch /var/log/cron.log
ADD backups.sh /backups.sh
ADD start.sh /start.sh
ADD cleanup.sh /cleanup.sh
ADD cleanup.py /cleanup.py
RUN chmod +x /cleanup.sh /cleanup.py
 
CMD ["/start.sh"]
