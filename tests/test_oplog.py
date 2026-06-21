import json
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
    cmd = f'source "{SCRIPT}" --__noop >/dev/null 2>&1; oplog_record {quoted}'
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr


def _log_path(home: Path) -> Path:
    return home / ".cache" / "apple-cleanup" / "operations.log"


def test_record_appends_one_line(tmp_path):
    _run_record(tmp_path, "trash", "2048", "/tmp/foo cache", "/tmp/.Trash/foo cache", "user_cache")
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    ts, session, action, size, path, dest, cat = lines[0].split("\t")
    assert action == "trash"
    assert size == "2048"
    assert path == "/tmp/foo cache"
    assert dest == "/tmp/.Trash/foo cache"
    assert cat == "user_cache"
    assert ts.isdigit()
    assert session != ""


def test_record_sanitizes_tabs_and_newlines(tmp_path):
    _run_record(tmp_path, "delete", "10", "/tmp/a\tb\nc", "", "logs")
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    assert lines[0].split("\t")[4] == "/tmp/a b c"


def test_opt_out_writes_nothing(tmp_path):
    _run_record(tmp_path, "trash", "1", "/tmp/x", "", "logs",
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
    cols = lines[0].split("\t")
    assert len(cols) == 7, cols
    assert cols[2] in ("trash", "delete")


def test_dry_run_records_nothing(tmp_path):
    victim = tmp_path / "Library" / "Caches" / "com.example.app"
    victim.mkdir(parents=True)
    (victim / "blob.bin").write_bytes(b"x" * 4096)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_DRYRUN="1")
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm "{victim}" "Example" >/dev/null 2>&1; true')
    subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert not _log_path(tmp_path).exists()


def test_force_rm_records_delete_action(tmp_path):
    # APPLE_CLEANUP_FORCE_RM=1 bypasses trash-first, so the permanent-delete
    # branch runs and must record action "delete".
    victim = tmp_path / "Library" / "Caches" / "com.example.app"
    victim.mkdir(parents=True)
    (victim / "blob.bin").write_bytes(b"x" * 4096)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_FORCE_RM="1")
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm "{victim}" "Example" >/dev/null 2>&1; true')
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    cols = lines[0].split("\t")
    assert len(cols) == 7, cols
    assert cols[2] == "delete"


def test_exclusion_path_no_double_count(tmp_path):
    # With an exclusion list set, safe_rm_contents delegates to safe_rm per
    # child (each records once) and must NOT add its own record. N children
    # must produce exactly N lines, never N+1.
    (tmp_path / ".Trash").mkdir()
    parent = tmp_path / "Library" / "Caches" / "bucket"
    parent.mkdir(parents=True)
    for i in range(3):
        child = parent / f"child{i}"
        child.mkdir()
        (child / "blob.bin").write_bytes(b"x" * 1024)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_EXCLUDE="/nonexistent-protect")
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm_contents "{parent}" "Bucket" >/dev/null 2>&1; true')
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 3, lines  # exactly one per child, no summary double-count


def test_rotation_truncates_when_over_cap(tmp_path):
    # Pre-fill the log past a tiny cap with legacy 5-col lines (simulating a
    # log written before the v2 upgrade), then record once in v2 format; the
    # writer should rotate to the most recent half before appending, keeping
    # it bounded, and must not crash on the legacy-format lines it rotates.
    log = _log_path(tmp_path)
    log.parent.mkdir(parents=True)
    log.write_text("".join(f"{i}\ttrash\t10\t/tmp/p{i}\tlogs\n" for i in range(200)))
    before = len(log.read_text().splitlines())
    _run_record(tmp_path, "trash", "10", "/tmp/new", "", "logs",
                env_extra={"APPLE_CLEANUP_OPLOG_MAX_BYTES": "200"})
    after_lines = log.read_text().splitlines()
    # Rotated to ~half the old size, plus the one new record, and far below the original.
    assert len(after_lines) < before
    # The newest record survived (v2, 7 cols), the oldest legacy lines were dropped.
    new_cols = after_lines[-1].split("\t")
    assert len(new_cols) == 7, new_cols
    assert new_cols[4] == "/tmp/new"
    assert after_lines[0].split("\t")[0] != "0"


def test_history_json_empty_is_array(tmp_path):
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--history-json"],
                         env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout) == []


def test_history_json_newest_first_with_fields(tmp_path):
    log = _log_path(tmp_path)
    log.parent.mkdir(parents=True)
    log.write_text(
        "100\ttrash\t2048\t/tmp/old\tuser_cache\n"
        "200\tdelete\t4096\t/tmp/new\tsystem_cache\n"
    )
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--history-json"],
                         env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    rows = json.loads(out.stdout)
    assert [r["ts"] for r in rows] == [200, 100]  # newest first
    assert rows[0]["action"] == "delete"
    assert rows[0]["recoverable"] is False
    assert rows[1]["recoverable"] is True
    assert rows[0]["bytes"] == 4096
    assert "size_human" in rows[0]
    assert rows[1]["path"] == "/tmp/old"


def test_history_json_skips_malformed_lines(tmp_path):
    log = _log_path(tmp_path)
    log.parent.mkdir(parents=True)
    log.write_text(
        "garbage line without tabs\n"
        "150\ttrash\t512\t/tmp/ok\tlogs\n"
    )
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--history-json"],
                         env=env, capture_output=True, text=True, timeout=30)
    rows = json.loads(out.stdout)
    assert len(rows) == 1
    assert rows[0]["path"] == "/tmp/ok"


def test_history_human_empty_shows_message(tmp_path):
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--lang", "en", "--history"],
                         env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert "No cleanup history yet" in out.stdout


def test_history_human_lists_records_newest_first(tmp_path):
    log = _log_path(tmp_path)
    log.parent.mkdir(parents=True)
    log.write_text(
        "100\ttrash\t2048\t/tmp/older\tuser_cache\n"
        "200\tdelete\t4096\t/tmp/newer\tsystem_cache\n"
    )
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--lang", "en", "--history"],
                         env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert "/tmp/newer" in out.stdout and "/tmp/older" in out.stdout
    # Newest first: /tmp/newer appears before /tmp/older.
    assert out.stdout.index("/tmp/newer") < out.stdout.index("/tmp/older")
