import os
import subprocess
import re
from datetime import datetime, timedelta
from base_retention_test import BaseRetentionTest


class TestRetentionS3(BaseRetentionTest):
    """
    Retention scripts are assumed to have already run.
    """

    # ------------------------------------------------------------------
    # S3 retention
    # ------------------------------------------------------------------
    def _parse_s3_datetime(self, parts):
        # parts: ['2025-12-22', '06:09', '3114', 's3://...']
        return datetime.strptime(
            f"{parts[0]} {parts[1]}",
            "%Y-%m-%d %H:%M",
        )

    def test_s3_retention_policy_applied(self):
        if self.remove_before <= 0:
            self.skipTest("S3 retention disabled")

        proc = subprocess.run(
            ["s3cmd", "ls", f"s3://{self.bucket}", "--recursive"],
            capture_output=True,
            text=True,
            check=True,
        )

        lines = proc.stdout.splitlines()
        self.assertTrue(lines, "No objects found in S3 bucket")

        cutoff = self.now - timedelta(days=self.remove_before)

        for line in lines:
            parts = line.split()
            if len(parts) < 4:
                continue

            path = parts[3]
            if "globals.sql" in path:
                continue

            obj_dt = self._parse_s3_datetime(parts)

            self.assertGreaterEqual(
                obj_dt,
                cutoff,
                f"Expired S3 backup still present: {path}",
            )

    def test_s3_consolidation(self):
        if self.consolidate_after <= 0:
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

            path = parts[3]
            if "globals.sql" in path:
                continue

            obj_dt = self._parse_s3_datetime(parts)
            if obj_dt >= cutoff:
                continue

            filename = os.path.basename(path)

            # PG_gis_gis.22-December-2025-06-09.dmp.gz
            match = re.match(
                r"(.+)\.(\d{2}-[A-Za-z]+-\d{4})-\d{2}-\d{2}\.",
                filename,
            )
            if not match:
                continue

            db, day = match.groups()
            key = f"{db}.{day}"

            buckets.setdefault(key, []).append(path)

        for key, files in buckets.items():
            self.assertEqual(
                len(files),
                1,
                f"Multiple S3 backups found after consolidation for {key}: {files}",
            )

    def test_s3_checksum_retention(self):
        if not self.checksum_validation:
            self.skipTest("S3 checksum validation disabled")

        proc = subprocess.run(
            ["s3cmd", "ls", f"s3://{self.bucket}", "--recursive"],
            capture_output=True,
            text=True,
            check=True,
        )

        objects = [
            line.split()[-1]
            for line in proc.stdout.splitlines()
            if "globals.sql" not in line
        ]
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
