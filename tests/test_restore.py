import os, json, subprocess
from pathlib import Path
REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"

def _write_log(home, lines):
    log = home / ".cache/apple-cleanup/operations.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("\n".join(lines) + "\n")
    return log

def _restore(home, *args):
    env = dict(os.environ, HOME=str(home), APPLE_CLEANUP_LANG="en")
    out = subprocess.run(["bash", str(SCRIPT), *args], env=env,
                         capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)

def test_restore_moves_file_back(tmp_path):
    home = tmp_path; trash = home / ".Trash"; trash.mkdir()
    dest = trash / "junk.txt"; dest.write_text("x")
    src = home / "junk.txt"  # parent (home) exists, src free
    _write_log(home, [f"1000\tsessA\ttrash\t1\t{src}\t{dest}\ttest"])
    res = _restore(home, "--restore-items", "1")
    assert res["success"] is True
    assert any(r["source"] == str(src) for r in res["restored"])
    assert src.exists() and not dest.exists()

def test_collision_renames(tmp_path):
    home = tmp_path; trash = home / ".Trash"; trash.mkdir()
    dest = trash / "junk.txt"; dest.write_text("new")
    src = home / "junk.txt"; src.write_text("existing")  # occupied
    _write_log(home, [f"1000\tsessA\ttrash\t1\t{src}\t{dest}\ttest"])
    res = _restore(home, "--restore-items", "1")
    assert (home / "junk.txt (restored)").exists()
    assert any(r["reason"] == "renamed" for r in res["restored"])

def test_protected_refused(tmp_path):
    home = tmp_path; trash = home / ".Trash"; trash.mkdir()
    dest = trash / "x"; dest.write_text("x")
    _write_log(home, [f"1000\tsessA\ttrash\t1\t/etc/hosts\t{dest}\ttest"])
    res = _restore(home, "--restore-items", "1")
    assert any(s["reason"] == "protected" for s in res["skipped"])
