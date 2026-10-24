"""Repository review fetches only metadata at the observed commit."""
import importlib.util
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).resolve().parents[1] / "runtime-state.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
sha = "a" * 40


def fake_run(command, seconds, consume):
    if command[0] == "git":
        assert command[-1] == "HEAD"
        consume((sha + "\tHEAD\n").encode())
    else:
        assert command[-1] == f"https://raw.githubusercontent.com/example/plugin/{sha}/manifest.json"
        consume(b'{"version":"1.7.0"}')
    return 0


with patch.object(runtime, "run", fake_run):
    assert runtime.review_repository("https://github.com/example/plugin.git") == {"commit": sha, "version": "1.7.0"}
    assert runtime.review_repository("git@github.com:example/plugin.git")["commit"] == sha
    for url in ["https://example.org/a/b", "https://github.com/a/../b", "https://github.com/a/b?x=y"]:
        try:
            runtime.review_repository(url)
        except ValueError:
            pass
        else:
            raise AssertionError(url)
print("review-repository-test: ok")

# Reviewed identity must reach the installer unchanged, including on failure.
class Store:
    def lock(self, name):
        from contextlib import nullcontext
        return nullcontext()

    def write(self, name, data):
        pass


commands = []
with patch.object(runtime, "run", lambda argv, seconds, consume: commands.append(argv) or 0):
    assert runtime.install("https://github.com/example/plugin.git", "test", sha, Store()) == 0
    assert commands[0][-3:] == ["--yes", "--commit", sha]
    for bad in ("", "HEAD", "--upload-pack=evil", sha + "/x"):
        try:
            runtime.install("https://github.com/example/plugin.git", "test", bad, Store())
        except ValueError:
            pass
        else:
            raise AssertionError(bad)
assert len(commands) == 1
