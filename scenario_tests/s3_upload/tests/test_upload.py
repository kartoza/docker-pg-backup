import subprocess
import unittest
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)


class TestUpload(unittest.TestCase):
    def setUp(self):
        self.s3_base_path = f"s3://{os.environ.get('BUCKET')}/"
        self.globals_dump_archive = 'globals.sql'
        self.dump_prefix = os.environ.get('DUMPPREFIX')
        self.checksum_validation = os.environ.get('CHECKSUM_VALIDATION')
        self.bucket = os.environ["BUCKET"]
        self.process = subprocess.run(["s3cmd", "ls", f"s3://{self.bucket}/"], capture_output=True, text=True,
                                      check=True)

    def test_compressed_backup_uploaded(self):
        """
        Checks if the s3 backup has was successful and the compressed dump file has been
        uploaded to the S3 backend bucket.

        Returns:
            bool: True if the operation was successful, False otherwise.
        """

        proc = subprocess.run([
            's3cmd',
            'ls',
            f"{self.s3_base_path}{self.globals_dump_archive}"
        ], capture_output=True)

        out_string = proc.stdout.decode('utf-8')
        self.assertTrue(out_string)
        logger.debug(out_string)

        proc = self.process

        archives = [
            line.split()[-1]
            for line in proc.stdout.splitlines()
            if line.endswith(".gz") and self.dump_prefix in line
        ]

        self.assertTrue(archives)

        latest = sorted(archives)[-1]
        logger.debug(f"Found archive: {latest}")

        latest = sorted(archives)[-1]
        logger.debug(f"Found archive: {latest}")

    def test_checksum_validation(self):
        proc = self.process

        objects = [line.split()[-1] for line in proc.stdout.splitlines()]
        gz_files = [o for o in objects if o.endswith(".gz")]

        self.assertTrue(gz_files, "No gz archive found")

        if str(self.checksum_validation).lower() == "true":

            for gz in gz_files:
                checksum = f"{gz}.sha256"
                self.assertIn(checksum, objects, f"Missing checksum for {gz}")
        else:

            for gz in gz_files:
                self.assertTrue(gz.endswith(".gz"), f"Unexpected non-gz file: {gz}")

    def test_checksum_not_uploaded_when_disabled(self):
        checksum_enabled = str(self.checksum_validation).lower() == "true"

        if checksum_enabled:
            return True

        # checksum validation is disabled — we must ensure no .sha256 files exist.
        proc = self.process
        objects = [line.split()[-1] for line in proc.stdout.splitlines()]

        checksum_files = [o for o in objects if o.endswith(".sha256")]

        self.assertFalse(
            checksum_files,
            f"Checksum files found when validation disabled: {checksum_files}"
        )

