#!/usr/bin/env python3
"""Private state and bounded process supervision for Omaplug (stdlib only)."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import selectors
import signal
import stat
import subprocess
import sys
import time

LIMIT = 131072
HERE = Path(__file__).resolve().parent


class PrivateDirectory:
    def __init__(self, path):
        path = Path(path)
        if not path.is_absolute() or ".." in path.parts or len(path.parts) < 3:
            raise ValueError("unsafe state directory")
        fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
        try:
            for part in path.parts[1:]:
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                os.close(fd)
                fd = child
                info = os.fstat(fd)
                sticky_root = info.st_mode & stat.S_ISVTX
                if (info.st_uid not in (0, os.getuid()) and not sticky_root) or (info.st_mode & 0o022 and not sticky_root):
                    raise ValueError("unsafe state ancestor")
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or info.st_mode & 0o022:
                raise ValueError("state directory must be privately owned")
            # Safely migrate an owned 0755 directory from previous versions.
            os.fchmod(fd, 0o700)
            self.fd = fd
        except BaseException:
            os.close(fd)
            raise

    def close(self):
        os.close(self.fd)

    def check(self, name):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", name):
            raise ValueError("invalid state name")
        try:
            info = os.stat(name, dir_fd=self.fd, follow_symlinks=False)
        except FileNotFoundError:
            return
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise ValueError("unsafe state file")
        if info.st_mode & 0o022:
            raise ValueError("writable shared state file")

    def write(self, name, data):
        self.check(name)
        if len(data) > LIMIT:
            raise ValueError("state exceeds size limit")
        temporary = ".tmp-" + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=self.fd)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd)
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(temporary, dir_fd=self.fd)

    def read(self, name):
        self.check(name)
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                raise ValueError("unsafe state file")
            data = stream.read(LIMIT + 1)
        if len(data) > LIMIT:
            raise ValueError("state exceeds size limit")
        return data

    @contextlib.contextmanager
    def lock(self, name):
        self.check(name)
        fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK,
                     0o600, dir_fd=self.fd)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                raise ValueError("unsafe lock file")
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield
        finally:
            os.close(fd)


def state_root():
    base = os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "omaplug"


def stop_child(child):
    # Descendants can keep stdout open after the leader exits.
    with contextlib.suppress(ProcessLookupError):
        os.killpg(child.pid, signal.SIGTERM)
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    with contextlib.suppress(ProcessLookupError):
        os.killpg(child.pid, signal.SIGKILL)
    child.wait()


def run(command, seconds, consume):
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    deadline = time.monotonic() + seconds
    total = 0
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while selector.get_map():
                if time.monotonic() >= deadline:
                    raise TimeoutError("operation timed out")
                for key, _ in selector.select(0.2):
                    chunk = os.read(key.fileobj.fileno(), 4096)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    total += len(chunk)
                    if total > LIMIT:
                        raise ValueError("process output exceeds limit")
                    consume(chunk)
            return child.wait(timeout=max(0.1, deadline - time.monotonic()))
    finally:
        stop_child(child)
        child.stdout.close()


def emit(data):
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def check_plugins(directory, store, coordinated=True):
    command = ["bash", str(HERE / "plugin-state.sh"), directory]
    # A fetch is bounded individually; allow the complete sequential inventory.
    count = min(1024, len(os.listdir(directory))) if os.path.isdir(directory) else 0
    deadline = min(3600, max(60, count * 20))
    output = bytearray()

    def consume(chunk):
        output.extend(chunk)
        emit(chunk)

    if not coordinated:
        return run(command, deadline, consume)
    waiting = False
    until = time.monotonic() + deadline
    while time.monotonic() < until:
        try:
            with store.lock("auto-check.flock"):
                if waiting:
                    data = json.loads(store.read("auto-check.cache"))
                    if data["directory"] != directory:
                        raise ValueError("cached check belongs to another plugin directory")
                    emit(data["output"].encode())
                    return data["code"]
                code = run(command, deadline, consume)
                store.write("auto-check.cache", json.dumps({"directory": directory,
                    "output": output.decode(errors="replace"), "code": code}).encode())
                return code
        except BlockingIOError:
            waiting = True
            time.sleep(1)
    raise TimeoutError("waiting for update check timed out")


def update(status, job, ids):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", job) or not 1 <= len(ids) <= 256:
        raise ValueError("invalid update job")
    path = Path(status)
    with contextlib.closing(PrivateDirectory(path.parent)) as store:
        with store.lock(path.name + ".flock"):
            store.check(path.name)
            output = bytearray()

            def consume(chunk):
                output.extend(chunk)
                store.write(path.name, bytes(output))

            return run(["bash", str(HERE / "update-helper.sh"), "--run", job, *ids],
                       min(3600, len(ids) * 140 + 30), consume)


def install(url, job, store):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", job):
        raise ValueError("invalid install job")
    if not re.fullmatch(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*/?", url) or ".." in url:
        raise ValueError("invalid GitHub repository URL")
    with store.lock("install.flock"):
        store.write("install.status", json.dumps({"job": job, "running": True, "pid": os.getpid()}).encode())
        output = bytearray()
        try:
            code = run(["timeout", "-k", "2", "180", "omarchy", "plugin", "add", url, "--yes"],
                       185, lambda chunk: output.extend(chunk[:max(0, 8000 - len(output))]))
            result = {"running": False, "failed": code != 0, "finished": int(time.time())}
        except (TimeoutError, ValueError, OSError) as error:
            result = {"running": False, "failed": True, "finished": int(time.time()), "error": str(error)}
        result["job"] = job
        store.write("install.status", json.dumps(result).encode())
        return int(result["failed"])


def main():
    os.umask(0o077)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    action, *args = sys.argv[1:]
    if action == "update":
        return update(args[0], args[1], args[2:])
    with contextlib.closing(PrivateDirectory(state_root())) as store:
        if action in ("check", "check-manual"):
            return check_plugins(args[0], store, action == "check")
        if action == "install":
            return install(args[0], args[1], store)
        if action == "read":
            emit(store.read(args[0]))
        elif action == "reopen-write":
            if args[0] not in ("layout", "main"):
                raise ValueError("invalid reopen page")
            store.write("reopen.status", json.dumps({"page": args[0], "time": time.time()}).encode())
        elif action == "reopen-read":
            with store.lock("reopen.flock"):
                data = json.loads(store.read("reopen.status"))
                os.unlink("reopen.status", dir_fd=store.fd)
                if time.time() - data["time"] > 10:
                    return 1
                print(data["page"])
        elif action != "read":
            raise ValueError("unknown action")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BlockingIOError:
        sys.exit(3)
    except (OSError, ValueError, IndexError, KeyError, TimeoutError) as error:
        print("omaplug: " + str(error), file=sys.stderr)
        sys.exit(2)
