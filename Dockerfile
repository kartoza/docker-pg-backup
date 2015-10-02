FROM kartoza/postgis:9.3-2.1
MAINTAINER tim@kartoza.com

RUN apt-get update
RUN apt-get install -y postgresql-client python-pip python-paramiko
RUN pip install --upgrade paramiko
ADD backups-cron /etc/cron.d/backups-cron
RUN touch /var/log/cron.log
ADD backups.sh /backups.sh
ADD start.sh /start.sh
ADD cleanup.sh /cleanup.sh
ADD cleanup.py /cleanup.py
ADD sftp_push.py /sftp_push.py
RUN chmod +x /cleanup.sh /cleanup.py
 
CMD ["/start.sh"]
