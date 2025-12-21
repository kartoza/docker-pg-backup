import os
from datetime import datetime, timedelta

from base_retention_test import BaseRetentionTest


class TestRetentionFile(BaseRetentionTest):
    """
    File-based retention tests (mtime-driven).
    """

    # ------------------------------------------------------------------
    # Local filesystem retention
    # ------------------------------------------------------------------

    def test_local_retention_policy_applied(self):
        """
        Validate local retention:
        - globals.sql preserved
        - at least MIN_SAVED_FILE backups kept
        - only the newest MIN_SAVED_FILE backups may be older than REMOVE_BEFORE
        """
        self.assertTrue(self.base_dir.exists(), "Backup directory missing")

        files = []

        for root, _, filenames in os.walk(self.base_dir):
            for name in filenames:
                files.append(os.path.join(root, name))

        # globals.sql must always exist
        self.assertTrue(
            any(os.path.basename(f) == "globals.sql" for f in files),
            "globals.sql missing after retention",
        )

        backup_files = sorted(
            [
                f for f in files
                if os.path.basename(f) != "globals.sql"
                and os.path.splitext(f)[1] in {".dmp", ".sql", ".gz"}
            ],
            key=lambda f: os.stat(f).st_mtime,
            reverse=True,  # newest first
        )

        self.assertGreaterEqual(
            len(backup_files),
            self.min_saved,
            "Minimum saved backups not preserved",
        )

        cutoff = self.now - timedelta(days=self.remove_before)

        protected = backup_files[: self.min_saved]
        candidates = backup_files[self.min_saved :]

        # All unprotected backups must respect REMOVE_BEFORE
        for f in candidates:
            mtime = datetime.fromtimestamp(os.stat(f).st_mtime)
            self.assertGreaterEqual(
                mtime,
                cutoff,
                f"Expired backup still present: {os.path.basename(f)}",
            )

    # ------------------------------------------------------------------
    # Consolidation
    # ------------------------------------------------------------------

    def test_local_consolidation(self):
        """
        Ensure only one backup per DB per day exists for
        backups older than CONSOLIDATE_AFTER.
        """
        if self.consolidate_after <= 0:
            self.skipTest("Consolidation disabled")

        cutoff = self.now - timedelta(days=self.consolidate_after)

        backups = []

        for root, _, filenames in os.walk(self.base_dir):
            for name in filenames:
                if name != "globals.sql":
                    backups.append(os.path.join(root, name))

        buckets = {}

        for f in backups:
            mtime = datetime.fromtimestamp(os.stat(f).st_mtime)
            if mtime >= cutoff:
                continue

            # Strip HH-MM from filename
            key = os.path.basename(f).rsplit("-", 2)[0]
            buckets.setdefault(key, []).append(f)

        for key, files in buckets.items():
            self.assertEqual(
                len(files),
                1,
                f"Multiple consolidated backups found for {key}: {files}",
            )