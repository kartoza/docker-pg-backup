#!/bin/bash

source /backup-scripts/env-data.sh

mkdir -p ${DEFAULT_EXTRA_CONF_DIR}
# Copy settings for cron file
export CRON_SCHEDULE
cron_config

# Fix variables not interpolated
sed -i "s/'//g" /backup-scripts/backups-cron
sed -i 's/\"//g' /backup-scripts/backups-cron

# Setup cron job
crontab /backup-scripts/backups-cron

cron -f
