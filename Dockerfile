FROM ubuntu:latest
MAINTAINER tim@kartoza.com
 
RUN apt-get install -y postgresql-client
ADD backups-cron /etc/cron.d/backups-cron
RUN touch /var/log/cron.log
ADD backups.sh /backups.sh
 
CMD cron -f
