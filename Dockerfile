FROM kartoza/postgis:12.1

RUN apt-get -y update; apt-get -y --no-install-recommends install postgresql-client cron awscli
RUN touch /var/log/cron.log

COPY backups-cron /backups-cron
COPY backups.sh /backups.sh
COPY restore.sh /restore.sh
COPY start.sh /start.sh
RUN chmod 0755 /*.sh

ENTRYPOINT ["/bin/bash", "/start.sh"]
CMD ["/docker-entrypoint.sh"]
