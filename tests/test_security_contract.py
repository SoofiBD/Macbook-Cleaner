import re
from pathlib import Path


REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"
SERVER = REPO / "web/server.py"


def _owning_shell_function(lines, index):
    function = "<top-level>"
    declaration = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\) \{")
    for line in lines[: index + 1]:
        match = declaration.match(line)
        if match:
            function = match.group(1)
    return function


def test_recursive_rm_is_confined_to_shared_removal_helpers():
    lines = SCRIPT.read_text().splitlines()
    allowed = {"safe_rm", "safe_rm_contents"}
    violations = []
    for index, line in enumerate(lines):
        code = line.split("#", 1)[0]
        if re.search(r"(?:^|\s)(?:sudo\s+)?rm\s+-[A-Za-z]*r[A-Za-z]*f?\s", code):
            owner = _owning_shell_function(lines, index)
            if owner not in allowed:
                violations.append((index + 1, owner, line.strip()))
    assert violations == []


def test_mutating_owner_commands_use_the_dry_run_gateway():
    source = SCRIPT.read_text()
    patterns = (
        r"run_mutating_action docker_cleaned docker_cleanup_failed\s+\\?\s*docker system prune -a -f --volumes",
        r"run_mutating_action brew_cleanup_success brew_cleanup_failed\s+\\?\s*brew cleanup -s",
        r"run_mutating_action simctl_deleted simctl_failed\s+\\?\s*xcrun simctl delete unavailable",
        r"run_mutating_action ql_reset ql_failed qlmanage -r cache",
    )
    for pattern in patterns:
        assert re.search(pattern, source), pattern


def test_launcher_never_recursively_clears_quarantine():
    launcher = (REPO / "CLICK_TO_START.command").read_text()
    assert "xattr -dr" not in launcher
    assert "xattr -r" not in launcher


def test_web_subprocesses_never_enable_shell_mode():
    source = SERVER.read_text()
    assert "shell=True" not in source
    assert "os.system(" not in source
