import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"


def _run_record(home: Path, *args, env_extra=None) -> None:
    """Source clean_mac.sh and call oplog_record directly with isolated HOME."""
    env = dict(os.environ, HOME=str(home))
    if env_extra:
        env.update(env_extra)
    quoted = " ".join(f"'{a}'" for a in args)
    cmd = f'source "{SCRIPT}" >/dev/null 2>&1; oplog_record {quoted}'
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr


def _log_path(home: Path) -> Path:
    return home / ".cache" / "apple-cleanup" / "operations.log"


def test_record_appends_one_line(tmp_path):
    _run_record(tmp_path, "trash", "2048", "/tmp/foo cache", "user_cache")
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    ts, action, size, path, cat = lines[0].split("\t")
    assert action == "trash"
    assert size == "2048"
    assert path == "/tmp/foo cache"
    assert cat == "user_cache"
    assert ts.isdigit()


def test_record_sanitizes_tabs_and_newlines(tmp_path):
    _run_record(tmp_path, "delete", "10", "/tmp/a\tb\nc", "logs")
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    assert lines[0].split("\t")[3] == "/tmp/a b c"


def test_opt_out_writes_nothing(tmp_path):
    _run_record(tmp_path, "trash", "1", "/tmp/x", "logs",
                env_extra={"APPLE_CLEANUP_NO_OPLOG": "1"})
    assert not _log_path(tmp_path).exists()
