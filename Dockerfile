FROM golang:1.9.2-stretch
MAINTAINER federico.facca@martel-innovate.com

RUN apt-get update
RUN apt-get install -y software-properties-common dirmngr
RUN go get github.com/odeke-em/drive/drive-gen && drive-gen
RUN apt-get install -y cron postgresql-client-9.6
RUN apt-get clean

USER root
WORKDIR /
ADD backups_cron /etc/cron.d/backups_cron
RUN touch /var/log/cron.log
ADD db-backups.sh db-backups.sh
ADD file-backups.sh file-backups.sh
ADD clean.sh clean.sh
ADD start.sh start.sh
RUN chmod +x start.sh
RUN chmod +x file-backups.sh
RUN chmod +x db-backups.sh
RUN chmod +x clean.sh


ENV ODOO_FILES 0
ENV DRIVE_DESTINATION ""

ENTRYPOINT ["bash", "start.sh"]