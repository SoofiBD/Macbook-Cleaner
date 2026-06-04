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
