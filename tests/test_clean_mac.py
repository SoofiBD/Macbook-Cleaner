# tests/test_clean_mac.py
import json
import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"


def run_scan(home: Path) -> dict:
    """clean_mac.sh --scan-json'u izole bir HOME ile çalıştır, JSON döndür."""
    env = dict(os.environ, HOME=str(home))
    out = subprocess.run(
        ["bash", str(SCRIPT), "--scan-json"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def make_dir_with_bytes(path: Path, kb: int) -> None:
    """path altında ~kb kilobayt veri oluştur."""
    path.mkdir(parents=True, exist_ok=True)
    (path / "blob.bin").write_bytes(b"x" * (kb * 1024))


def test_scan_json_has_required_keys(tmp_path):
    data = run_scan(tmp_path)
    assert data["success"] is True
    assert "scan" in data
    assert "total_bytes" in data
    # Her kategori size_bytes alanı taşımalı
    for cat_id, info in data["scan"].items():
        assert "size_bytes" in info, cat_id


def test_scan_json_includes_risk_per_category(tmp_path):
    data = run_scan(tmp_path)
    assert data["scan"]["browser_full"]["risk"] == "danger"
    assert data["scan"]["user_cache"]["risk"] == "safe"


def test_app_uninstaller_excluded_from_total(tmp_path):
    # app_uninstaller (in_total=0) yalnız bir alt-öğe üretebilir ama
    # total_bytes'a EKLENMEMELİ. Burada user_cache'e 2MB koyup
    # toplamın yalnızca onu içerdiğini doğruluyoruz.
    make_dir_with_bytes(tmp_path / "Library/Caches/com.example.app", kb=2048)
    data = run_scan(tmp_path)
    # app_uninstaller bytes'ı varsa bile total'a dahil olmamalı
    summed_in_total = sum(
        info["size_bytes"] for cid, info in data["scan"].items()
        if cid != "app_uninstaller"
    )
    assert data["total_bytes"] == summed_in_total


def test_app_leftovers_excludes_browser_dirs(tmp_path):
    # Chrome profili Application Support/Google altında; app_leftovers'a
    # sayılmamalı (browser_full sahibi).
    make_dir_with_bytes(
        tmp_path / "Library/Application Support/Google/Chrome", kb=4096)
    make_dir_with_bytes(
        tmp_path / "Library/Application Support/SomeApp", kb=1024)
    data = run_scan(tmp_path)
    leftovers = data["scan"]["app_leftovers"]["size_bytes"]
    # Yalnızca SomeApp (~1MB) sayılmalı, Google (~4MB) değil
    assert leftovers < 3 * 1024 * 1024, leftovers


def test_hardlinks_not_double_counted(tmp_path):
    import os as _os
    logs = tmp_path / "Library/Logs"
    logs.mkdir(parents=True)
    (logs / "a").mkdir()
    (logs / "b").mkdir()
    big = logs / "a" / "big.bin"
    big.write_bytes(b"y" * (5 * 1024 * 1024))  # 5MB
    _os.link(big, logs / "b" / "big_link.bin")  # aynı inode, kardeş dizinde
    data = run_scan(tmp_path)
    logs_size = data["scan"]["logs"]["size_bytes"]
    # Hardlink tek sayılmalı → ~5MB, 10MB değil
    assert logs_size < 8 * 1024 * 1024, logs_size


def run_clean(home, cats: str) -> dict:
    env = dict(os.environ, HOME=str(home))
    out = subprocess.run(
        ["bash", str(SCRIPT), "--clean-json", cats],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def test_clean_json_reports_real_and_estimated(tmp_path):
    # logs kategorisi (id index 4) — boş HOME'da silinecek bir şey yok.
    data = run_clean(tmp_path, "4")
    assert "freed_bytes" in data       # gerçek (df farkı)
    assert "estimated_bytes" in data   # du tahmini
    assert "freed_source" in data      # "df" veya "estimated"
    assert data["freed_bytes"] >= 0    # negatif kıstırılmış


def test_dry_run_previews_without_deleting(tmp_path):
    # user_cache (index 1) holds a 2MB blob; dry-run must report it as an
    # estimate but leave the file untouched on disk.
    blob = tmp_path / "Library/Caches/com.example.app/blob.bin"
    make_dir_with_bytes(blob.parent, kb=2048)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_DRYRUN="1")
    out = subprocess.run(
        ["bash", str(SCRIPT), "--clean-json", "1"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    data = json.loads(out.stdout)
    assert data["dry_run"] is True
    assert data["estimated_bytes"] > 0
    # File must still exist — nothing was actually removed.
    assert blob.exists(), "dry-run must not delete files"


def test_clean_json_reports_dry_run_flag(tmp_path):
    data = run_clean(tmp_path, "4")  # normal run
    assert data["dry_run"] is False


def test_exclusion_list_protects_path(tmp_path):
    caches = tmp_path / "Library/Caches"
    keep = caches / "keep.app"
    drop = caches / "drop.app"
    make_dir_with_bytes(keep, kb=512)
    make_dir_with_bytes(drop, kb=512)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_FORCE_RM="1",
               APPLE_CLEANUP_EXCLUDE=str(keep))
    out = subprocess.run(
        ["bash", str(SCRIPT), "--clean-json", "1"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    # clean_user_cache clears each cache dir's contents; the excluded dir's
    # payload must survive while the non-excluded one is removed.
    assert (keep / "blob.bin").exists(), "excluded path must survive cleaning"
    assert not (drop / "blob.bin").exists(), "non-excluded path should be removed"


def test_app_uninstaller_unknown_app_is_safe(tmp_path):
    # An app not present in /Applications resolves to an empty bundle id.
    # The cleaner must NEVER fall back to deleting whole Library subdirs
    # (e.g. ~/Library/Containers) when the bundle id is empty.
    keep = tmp_path / "Library/Containers/keepme"
    keep.mkdir(parents=True)
    (keep / "data").write_bytes(b"x" * 1024)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_FORCE_RM="1")
    out = subprocess.run(
        ["bash", str(SCRIPT), "--clean-json", "11",
         "--app-uninstaller-sub", "ZzNoSuchApp"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    assert (tmp_path / "Library/Containers/keepme/data").exists(), \
        "empty bundle id must not delete Library subdirectories"


def test_developer_subitems_include_new_caches(tmp_path):
    # Gradle cache fixture → developer subitems içinde gradle_cache görünmeli
    make_dir_with_bytes(tmp_path / ".gradle/caches/modules", kb=2048)
    data = run_scan(tmp_path)
    subs = data["scan"]["developer"].get("subitems", [])
    ids = {s["id"] for s in subs}
    assert "gradle_cache" in ids, ids
    g = next(s for s in subs if s["id"] == "gradle_cache")
    assert g["risk"] == "caution"
    assert g["size_bytes"] > 0


def test_new_system_categories_present(tmp_path):
    data = run_scan(tmp_path)
    for cid in ["diagnostic_reports", "quicklook_cache",
                "saved_app_state", "other_trash"]:
        assert cid in data["scan"], cid


def test_thin_snapshots_json_shape(tmp_path):
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_DRYRUN="1")
    out = subprocess.run(
        ["bash", str(SCRIPT), "--thin-snapshots-json"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    data = json.loads(out.stdout)
    assert "success" in data
    assert "snapshots_before" in data


def test_scan_json_includes_in_total_per_category(tmp_path):
    # Her kategori bir boolean in_total bayrağı taşımalı; client toplamı
    # yalnız in_total=true kategorilerden hesaplar (çift sayımı önler).
    data = run_scan(tmp_path)
    for cat_id, info in data["scan"].items():
        assert "in_total" in info, cat_id
        assert isinstance(info["in_total"], bool), cat_id
    # app_uninstaller, app_leftovers ile çakıştığı için total dışı olmalı.
    assert data["scan"]["app_uninstaller"]["in_total"] is False


def test_total_bytes_equals_in_total_sum(tmp_path):
    data = run_scan(tmp_path)
    expected = sum(
        info.get("size_bytes", 0)
        for info in data["scan"].values()
        if info.get("in_total")
    )
    assert data["total_bytes"] == expected
