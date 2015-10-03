#!/usr/bin/env python
# coding=utf-8
"""
Copy a backup file over using sftp

This module contains SFTP related backup method
"""
import os
import stat
from sys import argv

import paramiko
from paramiko.sftp_client import SFTPClient


__author__ = 'lucernae'
__email__ = 'lana.pcfre@gmail.com'


# initialize environment variable
try:
    use_sftp_backup = bool(os.environ['USE_SFTP_BACKUP'])
except KeyError:
    use_sftp_backup = False
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


def get_sftp_session():
    """Create SFTP Session based on env variable

    :return: SFTP client connection
    :rtype: SFTPClient
    """
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


def sftp_exists(sftp, path):
    try:
        sftp.stat(path)
    except IOError, e:
        # no file
        return False
    else:
        return True



def recursive_mkdir(sftp, dir_name):
    """Recursively create folder in sftp host

    :param sftp: Paramiko sftp client
    :type sftp: SFTPClient
    :param dir_name: directory name
    :type dir_name: str
    """
    head, _ = os.path.split(dir_name)
    if head:
        recursive_mkdir(sftp, head)

    # check path exists
    if not sftp_exists(sftp, dir_name):
        sftp.mkdir(dir_name)


def push_to_remote(filename):
    """Push a particular backup file to remote

    :param filename: File location of backup file in local
    :type filename: str
    """
    if use_sftp_backup:
        # get sftp session
        rel_path = os.path.relpath(filename, '/backups')
        dir_name, _ = os.path.split(rel_path)

        try:
            print "pushing %s" % rel_path
            sftp = get_sftp_session()
            recursive_mkdir(sftp, dir_name)
            sftp.put(filename, rel_path)
            sftp.close()
            print "push success"
        except Exception as e:
            print e.message


def push_backups_to_remote():
    """Push local backups to remote backups via SFTP

    This method will copy all local backups to remote server, overwriting it
    if any.
    """
    if use_sftp_backup:
        root_dir = '/backups'
        for root, dirs, files in os.walk(root_dir):
            for f in files:
                filename = os.path.join(root, f)
                push_to_remote(filename)


def sftp_walk(sftp, path, topdown=True):
    """Similar to os.walk but works for SFTP folders

    :param sftp: SFTPClient
    :type sftp: SFTPClient
    :param path: the path to look at
    :type path: str
    :return: tuple of (dirpath, dirs, files) similar with os.walk
    :rtype: tuple
    """
    items = sftp.listdir(path)
    dirs = []
    nondirs = []

    for i in items:
        filename = os.path.join(path, i)
        file_stat = sftp.stat(filename)
        if stat.S_ISDIR(file_stat.st_mode):
            dirs.append(i)
        else:
            nondirs.append(i)

    if topdown:
        yield path, dirs, nondirs

    for name in dirs:
        new_path = os.path.join(path, name)
        for x in sftp_walk(sftp, new_path, topdown):
            yield x

    if not topdown:
        yield path, dirs, nondirs


def pull_backups_from_remote():
    """Pull remote backups to local backups via SFTP

    This method will copy all remote backups to local server, overwriting it
    if any.
    """
    if use_sftp_backup:
        sftp = get_sftp_session()
        for root, dirs, files in sftp_walk(sftp, working_dir):
            for f in files:
                remote_filename = os.path.join(root, f)
                rel_path = os.path.relpath(remote_filename, working_dir)
                local_filename = os.path.join('/backups', rel_path)
                try:
                    print 'pulling %s' % rel_path
                    sftp.get(remote_filename, local_filename)
                    print 'pull success'
                except Exception as e:
                    print e.message

            for d in dirs:
                remote_dirname = os.path.join(root, d)
                rel_path = os.path.relpath(remote_dirname, working_dir)
                local_dirname = os.path.join('/backups', rel_path)
                try:
                    os.makedirs(local_dirname)
                except Exception as e:
                    print e.message


def main():
    """Push filename (arg 1) to sftp Remote
    """
    filename = argv[1]
    push_to_remote(filename)


if __name__ == '__main__':
    main()
