import os
import unittest
from datetime import datetime
from pathlib import Path


class BaseRetentionTest(unittest.TestCase):
    """
    Base class for retention tests.
    Loads environment variables and common setup.
    """

    def setUp(self):
        self.base_dir = Path(os.environ.get("MYBASEDIR", "/backups"))
        self.remove_before = int(os.environ.get("REMOVE_BEFORE", "3"))
        self.min_saved = int(os.environ.get("MIN_SAVED_FILE", "2"))
        self.consolidate_after = int(os.environ.get("CONSOLIDATE_AFTER", "0"))
        self.bucket = os.environ.get("BUCKET")
        self.dump_prefix = os.environ.get("DUMPPREFIX", "")
        self.checksum_validation = os.environ.get("CHECKSUM_VALIDATION", "false").lower() == "true"
        self.now = datetime.now()
