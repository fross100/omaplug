#!/usr/bin/env python3
"""Regression checks for plugin-folder layout moves, using an isolated config."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "plugin-folder-layout.py"


class PluginFolderLayoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config_home = Path(self.temp.name)
        config_dir = self.config_home / "omarchy"
        config_dir.mkdir()
        self.config_path = config_dir / "shell.json"
        self.config = {
            "bar": {
                "layout": {"left": ["first", {"id": "airdrop"}], "center": [], "right": ["last"]},
                "pluginFolder": {"widgets": []},
            },
            "theme": {"name": "kept"},
        }
        self.write_config()

    def write_config(self) -> None:
        self.config_path.write_text(json.dumps(self.config), encoding="utf-8")

    def run_helper(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = {**os.environ, "XDG_CONFIG_HOME": str(self.config_home)}
        return subprocess.run(
            ["python3", str(HELPER), *args],
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def read_config(self) -> dict:
        return json.loads(self.config_path.read_text(encoding="utf-8"))

    def test_move_to_folder_and_back_preserves_entry_shape_and_other_config(self) -> None:
        moved = self.run_helper("airdrop", "folder", "0")
        self.assertEqual(moved.returncode, 0, moved.stderr)
        config = self.read_config()
        self.assertEqual(config["bar"]["pluginFolder"]["widgets"], [{"id": "airdrop"}])
        self.assertEqual(config["bar"]["layout"]["left"], ["first"])
        self.assertEqual(config["theme"], {"name": "kept"})

        restored = self.run_helper("airdrop", "center", "0")
        self.assertEqual(restored.returncode, 0, restored.stderr)
        config = self.read_config()
        self.assertEqual(config["bar"]["pluginFolder"]["widgets"], [])
        self.assertEqual(config["bar"]["layout"]["center"], [{"id": "airdrop"}])

    def test_remove_drops_folder_entry(self) -> None:
        self.config["bar"]["pluginFolder"]["widgets"] = ["airdrop"]
        self.config["bar"]["layout"]["left"] = ["first"]
        self.write_config()
        result = self.run_helper("airdrop", "remove", "0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_config()["bar"]["pluginFolder"]["widgets"], [])

    def test_invalid_id_and_duplicate_entries_do_not_change_config(self) -> None:
        original = self.config_path.read_text(encoding="utf-8")
        invalid = self.run_helper("../airdrop", "folder", "0")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(self.config_path.read_text(encoding="utf-8"), original)

        self.config["bar"]["layout"]["right"].append("airdrop")
        self.write_config()
        original = self.config_path.read_text(encoding="utf-8")
        duplicate = self.run_helper("airdrop", "folder", "0")
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertEqual(self.config_path.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
