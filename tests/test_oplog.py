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


def test_real_trash_op_records_one_line(tmp_path):
    # Isolated HOME so the manual-mv trash fallback lands in tmp_path/.Trash.
    (tmp_path / ".Trash").mkdir()
    victim = tmp_path / "Library" / "Caches" / "com.example.app"
    victim.mkdir(parents=True)
    (victim / "blob.bin").write_bytes(b"x" * 4096)
    env = dict(os.environ, HOME=str(tmp_path))
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm "{victim}" "Example" >/dev/null 2>&1; true')
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    assert lines[0].split("\t")[1] in ("trash", "delete")


def test_dry_run_records_nothing(tmp_path):
    victim = tmp_path / "Library" / "Caches" / "com.example.app"
    victim.mkdir(parents=True)
    (victim / "blob.bin").write_bytes(b"x" * 4096)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_DRYRUN="1")
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm "{victim}" "Example" >/dev/null 2>&1; true')
    subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert not _log_path(tmp_path).exists()


def test_rotation_truncates_when_over_cap(tmp_path):
    # Pre-fill the log past a tiny cap, then record once; the writer should
    # rotate to the most recent half before appending, keeping it bounded.
    log = _log_path(tmp_path)
    log.parent.mkdir(parents=True)
    log.write_text("".join(f"{i}\ttrash\t10\t/tmp/p{i}\tlogs\n" for i in range(200)))
    before = len(log.read_text().splitlines())
    _run_record(tmp_path, "trash", "10", "/tmp/new", "logs",
                env_extra={"APPLE_CLEANUP_OPLOG_MAX_BYTES": "200"})
    after_lines = log.read_text().splitlines()
    # Rotated to ~half the old size, plus the one new record, and far below the original.
    assert len(after_lines) < before
    # The newest record survived, the oldest were dropped.
    assert after_lines[-1].split("\t")[3] == "/tmp/new"
    assert after_lines[0].split("\t")[0] != "0"
