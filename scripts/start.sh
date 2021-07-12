#!/bin/bash

source /backup-scripts/env-data.sh

# Copy settings for cron file
cron_config

crontab /backup-scripts/backups-cron

cron -f
