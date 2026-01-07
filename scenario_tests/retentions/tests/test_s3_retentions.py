import os
import re
import subprocess
import time
from datetime import datetime, timedelta

from base_retention_test import BaseRetentionTest

S3_LS_PATTERN = re.compile(
    r"^(?P<date>\d{4}-\d{2}-\d{2})\s+"
    r"(?P<time>\d{2}:\d{2})\s+"
    r"(?P<size>\d+)\s+"
    r"(?P<path>s3://.+)$"
)

BACKUP_PATTERN = re.compile(
    # PG_gis_gis.22-December-2025-06-09.dmp.gz
    r"(?P<db>.+)\."
    r"(?P<day>\d{2}-[A-Za-z]+-\d{4})-"
    r"\d{2}-\d{2}\."
)

# ------------------------------------------------------------------
# Port of extract_ts_from_filename (bash)
# ------------------------------------------------------------------
_TS_PATTERN = re.compile(
    r"\.(\d{2}-[A-Za-z]+-\d{4}-\d{2}-\d{2})\."
)


def extract_ts_from_filename(fname: str) -> int:
    """
    Bash-equivalent of extract_ts_from_filename()

    Returns epoch seconds, or 0 if no valid timestamp is found.
    """
    m = _TS_PATTERN.search(fname)
    if not m:
        return 0

    try:
        dt = datetime.strptime(m.group(1), "%d-%B-%Y-%H-%M")
    except ValueError:
        return 0

    # Match `date -d` local-time semantics
    return int(time.mktime(dt.timetuple()))


class TestRetentionS3(BaseRetentionTest):
    """
    Retention scripts are assumed to have already run.
    Tests validate *observable outcomes*, not script execution.
    """

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _run_s3_ls(self):
        try:
            proc = subprocess.run(
                ["s3cmd", "ls", f"s3://{self.bucket}", "--recursive"],
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            self.fail(f"s3cmd ls failed: {e.stderr or e.stdout}")

        lines = [l for l in proc.stdout.splitlines() if l.strip()]
        self.assertTrue(lines, "s3cmd returned no output")
        return lines

    def _parse_s3_line(self, line):
        """
        Returns (datetime, path) or None if line is not parseable.
        """
        match = S3_LS_PATTERN.match(line)
        if not match:
            return None

        try:
            obj_dt = datetime.strptime(
                f"{match.group('date')} {match.group('time')}",
                "%Y-%m-%d %H:%M",
            )
        except ValueError:
            return None

        return obj_dt, match.group("path")

    def _assert_now_is_valid(self):
        self.assertIsNotNone(self.now, "self.now must be set in BaseRetentionTest")
        self.assertIsInstance(self.now, datetime, "self.now must be datetime")

    # ------------------------------------------------------------------
    # Retention
    # ------------------------------------------------------------------
    def test_s3_retention_deletes_expired_objects(self):
        if self.remove_before <= 0:
            self.skipTest("S3 retention disabled")

        self._assert_now_is_valid()

        cutoff = int(
            (self.now - timedelta(days=self.remove_before)).timestamp()
        )

        expired = []

        for line in self._run_s3_ls():
            parsed = self._parse_s3_line(line)
            self.assertIsNotNone(parsed, f"Failed to parse s3cmd line: {line}")

            _, path = parsed

            # mirror shell logic
            if not path or path.endswith("globals.sql"):
                continue

            fname = os.path.basename(path)
            ts = extract_ts_from_filename(fname)

            # (( ts == 0 || ts >= cutoff )) && continue
            if ts == 0 or ts >= cutoff:
                continue

            expired.append((datetime.fromtimestamp(ts), path))

        if expired:
            details = "\n".join(
                f"{dt.isoformat()}  {path}" for dt, path in expired
            )
            self.fail(
                "Expired S3 backups still exist (retention violation):\n"
                f"{details}"
            )

        self.assertTrue(
            True,
            f"No S3 backups older than {self.remove_before} days found",
        )

    # ------------------------------------------------------------------
    # Consolidation
    # ------------------------------------------------------------------
    def test_s3_consolidation(self):
        if self.consolidate_after <= 0:
            self.skipTest("S3 consolidation disabled")

        self._assert_now_is_valid()
        cutoff = self.now - timedelta(days=self.consolidate_after)

        buckets = {}
        examined = 0

        for line in self._run_s3_ls():
            parsed_line = self._parse_s3_line(line)
            if not parsed_line:
                continue

            obj_dt, path = parsed_line
            if path.endswith("globals.sql"):
                continue

            if obj_dt >= cutoff:
                continue

            filename = os.path.basename(path)
            match = BACKUP_PATTERN.search(filename)
            if not match:
                continue

            examined += 1
            key = f"{match.group('db')}.{match.group('day')}"
            buckets.setdefault(key, []).append(path)

        self.assertGreater(
            examined,
            0,
            "No eligible backups found to validate consolidation",
        )

        for key, files in buckets.items():
            self.assertEqual(
                len(files),
                1,
                f"Multiple backups found after consolidation for {key}: {files}",
            )

    # ------------------------------------------------------------------
    # Checksums
    # ------------------------------------------------------------------
    def test_s3_checksum_retention(self):
        if not self.checksum_validation:
            self.skipTest("S3 checksum validation disabled")

        objects = []
        for line in self._run_s3_ls():
            parsed_line = self._parse_s3_line(line)
            if not parsed_line:
                continue

            _, path = parsed_line
            if path.endswith("globals.sql"):
                continue

            objects.append(path)

        gz_files = {o for o in objects if o.endswith(".gz")}
        sha_files = {o for o in objects if o.endswith(".sha256")}

        self.assertTrue(
            gz_files,
            "No .gz backups found to validate checksum retention",
        )

        # Forward check: every .gz has a checksum
        for gz in gz_files:
            self.assertIn(
                f"{gz}.sha256",
                sha_files,
                f"Missing checksum for {gz}",
            )

        # Reverse check: no orphaned checksums
        for sha in sha_files:
            base = sha[:-7]  # strip .sha256
            self.assertIn(
                base,
                gz_files,
                f"Orphaned checksum without data file: {sha}",
            )
