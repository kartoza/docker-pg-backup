import subprocess
import unittest
import os
import logging
from datetime import datetime

from utils.utils import DBConnection


logger = logging.getLogger(__name__)


class TestRestore(unittest.TestCase):

    def setUp(self):
        self.db = DBConnection()

    def test_archive_uploaded(self):
        s3_base_path = f"s3://{os.environ.get('BUCKET')}/"
        globals_dump_archive = 'globals.sql'
        dump_prefix = os.environ.get('DUMPPREFIX')
        db_name = 'gis'

        current_archive = datetime.now().strftime(
            f"%Y/%B/"
            f"{dump_prefix}_{db_name}.%d-%B-%Y.dmp")

        proc = subprocess.run([
            's3cmd',
            'ls',
            f"{s3_base_path}{globals_dump_archive}"
        ], capture_output=True)
        out_string = proc.stdout.decode('utf-8')
        self.assertTrue(out_string)
        logger.debug(out_string)

        proc = subprocess.run([
            's3cmd',
            'ls',
            f"{s3_base_path}{current_archive}"
        ], capture_output=True)
        out_string = proc.stdout.decode('utf-8')
        self.assertTrue(out_string)
        logger.debug(out_string)
