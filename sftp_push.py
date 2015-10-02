#!/usr/bin/env python
# coding=utf-8
"""
Copy a backup file over using sftp
"""
import os
from sys import argv
import paramiko
from paramiko.sftp_client import SFTPClient

__author__ = 'lucernae'


def recursive_mkdir(sftp, dir_name):
    """Recursively create folder in sftp host

    :param sftp: Paramiko sftp client
    :param dir_name: directory name
    """
    head, _ = os.path.split(dir_name)

    print 'dirname %s' % dir_name
    print 'head %s' % head
    if head:
        recursive_mkdir(sftp, head)
        try:
            sftp.mkdir(dir_name)
        except Exception:
            pass
    else:
        try:
            sftp.mkdir(head)
        except Exception:
            pass


if __name__ == '__main__':

    host = os.environ['SFTP_HOST']
    user = os.environ['SFTP_USER']
    password = os.environ['SFTP_PASSWORD']
    working_dir = os.environ['SFTP_DIR']
    filename = argv[1]

    rel_path = os.path.relpath(filename, '/backups')
    dir_name, _ = os.path.split(rel_path)
    print filename
    print rel_path
    print working_dir
    print dir_name

    transport = paramiko.Transport(host)
    transport.connect(username=user, password=password)
    sftp = SFTPClient.from_transport(transport)
    sftp.chdir(working_dir)
    recursive_mkdir(sftp, dir_name)
    sftp.put(filename, rel_path)
    sftp.close()


