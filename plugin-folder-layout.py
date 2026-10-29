#!/usr/bin/env python3
"""Move a bar widget between the regular layout and Omaplug's plugin folder."""

from __future__ import annotations

import fcntl
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path


WIDGET_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SECTIONS = ("left", "center", "right")
TARGETS = {*SECTIONS, "folder", "remove"}


def entry_id(entry: object) -> str:
    if isinstance(entry, dict):
        return str(entry.get("id", ""))
    return str(entry or "")


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: plugin-folder-layout.py WIDGET_ID TARGET_SECTION INDEX", file=sys.stderr)
        return 2

    widget_id, target, raw_index = sys.argv[1:]
    if not WIDGET_ID.fullmatch(widget_id) or ".." in widget_id:
        print("invalid widget id", file=sys.stderr)
        return 2
    if target not in TARGETS:
        print(f"invalid target section: {target}", file=sys.stderr)
        return 2
    try:
        index = max(0, int(raw_index))
    except ValueError:
        print(f"invalid index: {raw_index}", file=sys.stderr)
        return 2

    config_path = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "omarchy/shell.json"
    if not config_path.is_file():
        return fail(f"shell configuration not found: {config_path}")

    lock_path = config_path.with_name("shell.json.plugin-folder.lock")
    lock_fd = -1
    try:
        if config_path.is_symlink():
            return fail("shell configuration must not be a symbolic link")
        lock_flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
        lock_fd = os.open(lock_path, lock_flags, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        config_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(config_path, config_flags), "r", encoding="utf-8") as config_file:
            original = config_file.read()
        config = json.loads(original)
        if not isinstance(config, dict):
            return fail("shell configuration must be a JSON object")
        bar = config.setdefault("bar", {})
        if not isinstance(bar, dict):
            return fail("bar configuration must be an object")
        layout = bar.setdefault("layout", {})
        if not isinstance(layout, dict):
            return fail("bar.layout must be an object")
        folder_config = bar.setdefault("pluginFolder", {})
        if not isinstance(folder_config, dict):
            return fail("bar.pluginFolder must be an object")
        folder = folder_config.setdefault("widgets", [])
        if not isinstance(folder, list):
            return fail("bar.pluginFolder.widgets must be an array")

        locations: list[tuple[list[object], int]] = []
        for section in SECTIONS:
            entries = layout.setdefault(section, [])
            if not isinstance(entries, list):
                return fail(f"bar.layout.{section} must be an array")
            locations.extend((entries, pos) for pos, entry in enumerate(entries) if entry_id(entry) == widget_id)
        locations.extend((folder, pos) for pos, entry in enumerate(folder) if entry_id(entry) == widget_id)
        if len(locations) != 1:
            return fail("widget must occur exactly once in the bar layout or plugin folder")

        source, source_index = locations[0]
        moving = source.pop(source_index)
        if target == "folder":
            folder.insert(min(index, len(folder)), moving)
        elif target in SECTIONS:
            destination = layout[target]
            destination.insert(min(index, len(destination)), moving)

        updated = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
        mode = stat.S_IMODE(config_path.stat().st_mode)
        fd, temp_name = tempfile.mkstemp(prefix=".shell.json.", dir=config_path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(updated)
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temp_name, mode)
            os.replace(temp_name, config_path)
            directory_fd = os.open(config_path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"could not update shell configuration: {exc}")
    finally:
        if lock_fd >= 0:
            os.close(lock_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
