# tests/test_oplog_v2.py
import os, subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"

def _run(home, src):
    """Trash a single file via safe_rm using an isolated HOME, return oplog lines."""
    env = dict(os.environ, HOME=str(home), APPLE_CLEANUP_LANG="en")
    # Source a tiny harness that calls safe_rm on one file.
    code = f'source "{SCRIPT}" --__noop 2>/dev/null; _CURRENT_CATEGORY=test; safe_rm "{src}" "{src}"'
    subprocess.run(["bash", "-c", code], env=env, capture_output=True, text=True, timeout=60)
    log = home / ".cache/apple-cleanup/operations.log"
    return log.read_text().splitlines() if log.exists() else []

def test_trash_record_is_7_columns_with_session_and_dest(tmp_path):
    home = tmp_path / "home"; (home / ".Trash").mkdir(parents=True)
    src = home / "junk.txt"; src.write_text("data")
    lines = _run(home, src)
    assert len(lines) == 1
    cols = lines[0].split("\t")
    assert len(cols) == 7, cols
    ts, session, action, _bytes, source, dest, cat = cols
    assert action == "trash"
    assert session != ""
    assert source == str(src)
    assert dest.startswith(str(home / ".Trash"))
    assert cat == "test"
