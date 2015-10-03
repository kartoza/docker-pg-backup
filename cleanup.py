#!/usr/bin/env python
# coding=utf-8
"""
Cleanup scripts to clean unnecessary backup in local and remote
"""
import os
from datetime import datetime, timedelta
import math
import sftp_remote
from sftp_remote import get_sftp_session


__author__ = 'lucernae'
__email__ = 'lana.pcfre@gmail.com'


def main():
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

    # just get a localtime because we are dealing with the same timezone
    today = datetime.now()

    # iterate over the files
    # iterate bottom up, because we want to delete things
    root_folder = '/backups'
    for root, dirs, files in os.walk(root_folder, topdown=False):
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
                    # delete remote backup

                    if sftp_remote.use_sftp_backup:
                        # create sftp link
                        sftp = get_sftp_session()
                        rel_path = os.path.relpath(file_path, root_folder)
                        try:
                            print 'remove %s' % rel_path
                            sftp.remove(rel_path)
                            sftp.close()
                        except Exception as e:
                            print e.message

            except ValueError:
                continue

        # process dirs
        for d in dirs:
            dir_path = os.path.join(root, d)

            # delete empty directory
            if not os.listdir(dir_path):
                os.removedirs(dir_path)

                if sftp_remote.use_sftp_backup:
                    # create sftp link
                    sftp = get_sftp_session()
                    rel_path = os.path.relpath(dir_path, root_folder)
                    try:
                        print 'remove folder %s' % rel_path
                        sftp.rmdir(rel_path)
                        sftp.close()
                    except Exception as e:
                        print e.message


if __name__ == '__main__':
    main()
