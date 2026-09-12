#!/usr/bin/env python3
"""Isolated filesystem regressions; never touches installed plugins."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StateSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="omaplug-security-")
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.path))
        (self.path / "omaplug").mkdir(mode=0o700)
        (self.path / "plugins").mkdir()
        self.victim = self.path / "victim"
        self.victim.write_text("keep me")

    def run_helper(self, *args):
        return subprocess.run(args, env=self.env, capture_output=True, timeout=10)

    def test_cache_symlink_never_truncates_target(self):
        (self.path / "omaplug/auto-check.cache.tmp").symlink_to(self.victim)
        self.run_helper("bash", str(ROOT / "auto-check-coordinator.sh"), str(self.path / "plugins"))
        self.assertEqual(self.victim.read_text(), "keep me")

    def test_update_status_symlink_is_rejected(self):
        status = self.path / "update.status"
        status.symlink_to(self.victim)
        result = self.run_helper("bash", str(ROOT / "update-helper.sh"), str(status), "test", "invalid/id")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.victim.read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()
