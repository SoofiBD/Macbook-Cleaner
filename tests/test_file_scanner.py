"""Real temporary files exercise discovery, content checks and stale-file races."""
import os
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'web'))
import file_scanner
from file_scanner import scan_files


def test_large_files_use_actual_size_and_refresh(tmp_path):
    target = tmp_path / 'real.dmg'
    target.write_bytes(b'x' * 100)
    (tmp_path / 'small').write_bytes(b'x')
    first = scan_files('large', tmp_path, large_bytes=100)
    assert [r['path'] for r in first['results']] == [str(target)]
    assert first['results'][0]['size_bytes'] == 100
    target.unlink()
    assert scan_files('large', tmp_path, large_bytes=100)['results'] == []


def test_duplicates_require_identical_content_not_name_or_size(tmp_path):
    for name, data in [('a', b'abc'), ('b', b'abc'), ('c', b'xyz'), ('empty', b'')]:
        (tmp_path / name).write_bytes(data)
    os.link(tmp_path / 'a', tmp_path / 'hardlink')
    (tmp_path / 'symlink').symlink_to(tmp_path / 'a')
    groups = scan_files('duplicates', tmp_path)['results']
    assert len(groups) == 1
    assert [r['name'] for r in groups[0]['files']] == ['a', 'b']
    assert groups[0]['duplicate_bytes'] == 3
    (tmp_path / 'b').unlink()
    assert scan_files('duplicates', tmp_path)['results'] == []


def test_excludes_hidden_app_data_bundles_and_external_links(tmp_path):
    for folder in ['Library', '.secret', 'Tool.app', 'node_modules']:
        (tmp_path / folder).mkdir()
        (tmp_path / folder / 'data').write_bytes(b'test')
    (tmp_path / 'alias').symlink_to(tmp_path / 'Library', target_is_directory=True)
    assert scan_files('large', tmp_path, large_bytes=1)['results'] == []


def test_limits_and_unreadable_files_are_reported(tmp_path):
    (tmp_path / 'a').write_bytes(b'abc')
    (tmp_path / 'b').write_bytes(b'abc')
    assert scan_files('large', tmp_path, timeout=0)['partial']
    assert scan_files('large', tmp_path, max_entries=1)['partial']
    data = scan_files('duplicates', tmp_path, max_hash_bytes=1)
    assert data['partial'] and not data['results']
    with patch.object(file_scanner, '_digest', side_effect=PermissionError):
        data = scan_files('duplicates', tmp_path)
    assert data['partial'] and data['skipped_errors'] == 2


def test_changed_or_removed_files_not_published_as_duplicates(tmp_path):
    a, b = tmp_path / 'a', tmp_path / 'b'
    a.write_bytes(b'abc')
    b.write_bytes(b'abc')
    original = file_scanner._digest

    def racing_digest(path, *args):
        digest = original(path, *args)
        if path == str(b):
            a.unlink()
        return digest

    with patch.object(file_scanner, '_digest', side_effect=racing_digest):
        data = scan_files('duplicates', tmp_path)
    assert data['results'] == []
    assert data['partial']


def test_replaced_symlink_is_never_hashed(tmp_path):
    file = tmp_path / 'a'
    file.write_bytes(b'abc')
    identity = file_scanner._identity(file.stat())
    file.unlink()
    file.symlink_to('/etc/hosts')
    import pytest
    with pytest.raises(OSError):
        file_scanner._digest(str(file), identity, float('inf'), [100])


def test_dashboard_category_ids_match_server_contract():
    import re
    import server
    source = (Path(__file__).resolve().parents[1] / 'web/script.js').read_text()
    keys = re.findall(r"\bkey: '([^']+)'", source)
    assert len(keys) == len(set(keys))
    assert set(keys) == set(server._CATEGORY_IDS)
