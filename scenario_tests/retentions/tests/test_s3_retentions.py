import os
import subprocess
import unittest
from datetime import datetime, timedelta
from pathlib import Path


class TestRetention(unittest.TestCase):
    """
    Retention scripts are assumed to have already run.
    """

    def setUp(self):

        self.base_dir = Path(os.environ.get("MYBASEDIR", "/backups"))
        self.remove_before = int(os.environ.get("REMOVE_BEFORE", "7"))
        self.min_saved = int(os.environ.get("MIN_SAVED_FILE", "2"))
        self.consolidate_after = int(os.environ.get("CONSOLIDATE_AFTER", "1"))

        self.enable_s3 = str(os.environ.get("ENABLE_S3_BACKUP", "false")).lower() == "true"
        self.bucket = os.environ.get("S3_BUCKET")
        self.dump_prefix = os.environ.get("DUMPPREFIX", "")
        self.checksum_validation = str(
            os.environ.get("CHECKSUM_VALIDATION", "false")
        ).lower() == "true"

        self.now = datetime.now()

    # ------------------------------------------------------------------
    # S3 retention
    # ------------------------------------------------------------------

    def test_s3_retention_policy_applied(self):
        if not self.enable_s3:
            self.skipTest("S3 retention disabled")

        self.assertTrue(self.bucket, "S3_BUCKET not set")

        proc = subprocess.run(
            ["s3cmd", "ls", f"s3://{self.bucket}", "--recursive"],
            capture_output=True,
            text=True,
            check=True,
        )

        lines = proc.stdout.splitlines()
        self.assertTrue(lines, "No objects found in S3 bucket")

        objects = [line.split()[-1] for line in lines]

        # globals.sql must exist
        self.assertTrue(
            any(o.endswith("globals.sql") for o in objects),
            "globals.sql missing from S3 after retention",
        )

        cutoff = self.now - timedelta(days=self.remove_before)

        for line in lines:
            parts = line.split()
            if len(parts) < 4:
                continue

            date_str = parts[0]
            path = parts[3]

            if "globals.sql" in path:
                continue

            obj_date = datetime.strptime(date_str, "%Y-%m-%d")

            self.assertGreaterEqual(
                obj_date,
                cutoff,
                f"Expired S3 backup still present: {path}",
            )

    def test_s3_consolidation(self):
        if not self.enable_s3 or self.consolidate_after <= 0:
            self.skipTest("S3 consolidation disabled")

        proc = subprocess.run(
            ["s3cmd", "ls", f"s3://{self.bucket}", "--recursive"],
            capture_output=True,
            text=True,
            check=True,
        )

        cutoff = self.now - timedelta(days=self.consolidate_after)
        buckets = {}

        for line in proc.stdout.splitlines():
            parts = line.split()
            if len(parts) < 4:
                continue

            date_str, path = parts[0], parts[3]
            if "globals.sql" in path:
                continue

            obj_date = datetime.strptime(date_str, "%Y-%m-%d")
            if obj_date >= cutoff:
                continue

            filename = os.path.basename(path)
            key = filename.rsplit("-", 2)[0]
            buckets.setdefault(key, []).append(path)

        for key, files in buckets.items():
            self.assertEqual(
                len(files),
                1,
                f"Multiple S3 consolidated backups found for {key}: {files}",
            )

    def test_s3_checksum_retention(self):
        if not self.enable_s3:
            self.skipTest("S3 disabled")

        proc = subprocess.run(
            ["s3cmd", "ls", f"s3://{self.bucket}", "--recursive"],
            capture_output=True,
            text=True,
            check=True,
        )

        objects = [line.split()[-1] for line in proc.stdout.splitlines()]
        gz_files = [o for o in objects if o.endswith(".gz")]
        sha_files = [o for o in objects if o.endswith(".sha256")]

        if self.checksum_validation:
            for gz in gz_files:
                self.assertIn(
                    f"{gz}.sha256",
                    objects,
                    f"Missing checksum for {gz}",
                )
        else:
            self.assertFalse(
                sha_files,
                f"Checksum files found when disabled: {sha_files}",
            )
