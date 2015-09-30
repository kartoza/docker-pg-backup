#!/usr/bin/env python
# coding=utf-8
"""
Cleanup scripts to clean unnecessary backup
"""
import os
from datetime import datetime, timedelta
import math

__author__ = 'lucernae'


if __name__ == '__main__':

    log_file = open('/logfile', 'w+')
    # get how many backups needs to be persisted
    db_prefix = os.environ['DUMPPREFIX']
    db_name = os.environ['PGDATABASE']

    try:
        daily = int(os.environ['DAILY'])
    except KeyError:
        daily = 7
    try:
        monthly = int(os.environ['MONTHLY'])
    except KeyError:
        monthly = 12
    try:
        yearly = int(os.environ['YEARLY'])
    except KeyError:
        yearly = 3

    log_file.write('%s\n' % daily)
    log_file.write('%s\n' % monthly)
    log_file.write('%s\n' % yearly)

    # just get a localtime because we are dealing with the same timezone
    today = datetime.now()

    log_file.write('%s\n' % today)

    # iterate over the files
    # iterate bottom up, because we want to delete things
    for root, dirs, files in os.walk("/backups", topdown=False):
        # process files
        for f in files:
            # extract timestamp from name in the format:
            time_format = '%d-%B-%Y'
            dump_format = '%s_%s.%s.dmp' % (
                db_prefix,
                db_name,
                time_format
            )
            try:
                dump_time = datetime.strptime(f, dump_format)

                file_path = os.path.join(root, f)
                time_diff = today - dump_time

                # is it yearly dump?
                if dump_time.month == 1 and dump_time.day == 1:
                    # check the dump is within yearly interval
                    # timedelta doesn't have year constructor
                    # our best bet is using 365.25 days as 1 year ceiled
                    num_days = math.ceil(yearly * 365.25)

                # is it a monthly dump?
                elif dump_time.day == 1:
                    # check the dump is within monthly interval
                    # timedelta doesn't have month constructor
                    # our best bet is using 30.5 days as 1 month
                    num_days = math.ceil(monthly * 30.5)
                # calculate this using daily interval
                else:
                    num_days = daily

                interval = timedelta(days=num_days)
                if time_diff > interval:
                    os.remove(file_path)

            except ValueError:
                continue

        # process dirs
        for d in dirs:
            dir_path = os.path.join(root, d)

            # delete empty directory
            if not os.listdir(dir_path):
                os.removedirs(dir_path)

    log_file.close()
