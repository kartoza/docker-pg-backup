import subprocess
import unittest
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)


class TestRestore(unittest.TestCase):

    def test_archive_uploaded(self):
        s3_base_path = f"s3://{os.environ.get('BUCKET')}/"

        globals_dump_archive = 'globals.sql'
        dump_prefix = os.environ.get('DUMPPREFIX')

        proc = subprocess.run([
            's3cmd',
            'ls',
            f"{s3_base_path}{globals_dump_archive}"
        ], capture_output=True)

        out_string = proc.stdout.decode('utf-8')
        self.assertTrue(out_string)
        logger.debug(out_string)

        proc = subprocess.run(
            ["s3cmd", "ls", f"{s3_base_path}"],
            capture_output=True,
            text=True
        )
        print(proc)

        archives = [
            line.split()[-1]
            for line in proc.stdout.splitlines()
            if line.endswith(".gz") and dump_prefix in line
        ]
        print(archives)

        self.assertTrue(archives)

        latest = sorted(archives)[-1]
        logger.debug(f"Found archive: {latest}")
