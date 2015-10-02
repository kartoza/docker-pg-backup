#!/usr/bin/env python
# coding=utf-8
"""
Cleanup scripts to clean unnecessary backup
"""
import os
from datetime import datetime, timedelta
import math
import paramiko
from paramiko.sftp_client import SFTPClient

__author__ = 'lucernae'


def get_sftp_session(host, user, password, working_dir):
    conn = None
    try:
        transport = paramiko.Transport(host)
        transport.connect(username=user, password=password)
        conn = SFTPClient.from_transport(transport)
        conn.chdir(working_dir)
        print 'SFTP connection created'
    except Exception as e:
        print e.message
        pass
    return conn


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
    try:
        host = os.environ['SFTP_HOST']
    except KeyError:
        host = 'localhost'
    try:
        user = os.environ['SFTP_USER']
    except KeyError:
        user = 'user'
    try:
        password = os.environ['SFTP_PASSWORD']
    except KeyError:
        password = 'password'
    try:
        working_dir = os.environ['SFTP_DIR']
    except KeyError:
        working_dir = '/'

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
                    # os.remove(file_path)
                    # delete remote backup

                    # create sftp link
                    sftp = get_sftp_session(host, user, password, working_dir)
                    rel_path = os.path.relpath(file_path, root_folder)
                    try:
                        sftp.remove(rel_path)
                        sftp.close()
                    except IOError as e:
                        print e.message
                        pass

            except ValueError:
                continue

        # process dirs
        for d in dirs:
            dir_path = os.path.join(root, d)

            # delete empty directory
            if not os.listdir(dir_path):
                # os.removedirs(dir_path)

                # create sftp link
                sftp = get_sftp_session(host, user, password, working_dir)
                rel_path = os.path.relpath(dir_path, root_folder)
                try:
                    sftp.rmdir(rel_path)
                    sftp.close()
                except IOError as e:
                    print e.message
                    pass


if __name__ == '__main__':
    main()
