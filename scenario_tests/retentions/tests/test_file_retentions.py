import os
import unittest
import subprocess
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
    # Local filesystem retention
    # ------------------------------------------------------------------

    def test_local_retention_policy_applied(self):
        """
        Validate local retention:
        - old files removed
        - minimum backups kept
        - globals.sql preserved
        """
        self.assertTrue(self.base_dir.exists(), "Backup directory missing")

        files = list(self.base_dir.glob("*"))

        # globals.sql must always exist
        globals_files = [f for f in files if f.name == "globals.sql"]
        self.assertTrue(globals_files, "globals.sql missing after retention")

        backup_files = [
            f for f in files
            if f.is_file()
            and f.name != "globals.sql"
            and f.suffix in {".dmp", ".sql", ".gz"}
        ]

        self.assertGreaterEqual(
            len(backup_files),
            self.min_saved,
            "Minimum saved backups not preserved",
        )

        cutoff = self.now - timedelta(days=self.remove_before)

        for f in backup_files:
            mtime = datetime.fromtimestamp(f.stat().st_mtime)
            self.assertGreaterEqual(
                mtime,
                cutoff,
                f"Expired backup still present: {f.name}",
            )

    def test_local_consolidation(self):
        """
        Ensure only one backup per DB per day exists for
        backups older than CONSOLIDATE_AFTER.
        """
        if self.consolidate_after <= 0:
            self.skipTest("Consolidation disabled")

        cutoff = self.now - timedelta(days=self.consolidate_after)

        backups = [
            f for f in self.base_dir.glob("*")
            if f.is_file() and f.name != "globals.sql"
        ]

        buckets = {}

        for f in backups:
            mtime = datetime.fromtimestamp(f.stat().st_mtime)
            if mtime >= cutoff:
                continue

            # Strip HH-MM from filename
            key = f.name.rsplit("-", 2)[0]
            buckets.setdefault(key, []).append(f)

        for key, files in buckets.items():
            self.assertEqual(
                len(files),
                1,
                f"Multiple consolidated backups found for {key}: {files}",
            )

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