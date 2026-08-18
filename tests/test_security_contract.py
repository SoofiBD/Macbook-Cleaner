import re
from pathlib import Path


REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"
SERVER = REPO / "web/server.py"
SHELL_SOURCES = [SCRIPT, *sorted((REPO / "lib").rglob("*.sh"))]


def _owning_shell_function(lines, index):
    function = "<top-level>"
    declaration = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\) \{")
    for line in lines[: index + 1]:
        match = declaration.match(line)
        if match:
            function = match.group(1)
    return function


def test_recursive_rm_is_confined_to_shared_removal_helpers():
    allowed = {"safe_rm", "safe_rm_contents"}
    violations = []
    for source_path in SHELL_SOURCES:
        lines = source_path.read_text().splitlines()
        for index, line in enumerate(lines):
            code = line.split("#", 1)[0]
            if re.search(r"(?:^|\s)(?:sudo\s+)?rm\s+-[A-Za-z]*r[A-Za-z]*f?\s", code):
                owner = _owning_shell_function(lines, index)
                if owner not in allowed:
                    violations.append(
                        (str(source_path.relative_to(REPO)), index + 1, owner, line.strip())
                    )
    assert violations == []


def test_path_policy_has_single_module_definition():
    main_source = SCRIPT.read_text()
    executor_source = (REPO / "lib/core/executor.sh").read_text()
    module_source = (REPO / "lib/core/path_policy.sh").read_text()
    assert 'source "$SCRIPT_DIR/lib/core/executor.sh"' in main_source
    assert 'source "$SCRIPT_DIR/lib/core/path_policy.sh"' in executor_source
    assert "_validate_removal_path()" not in main_source
    assert module_source.count("_validate_removal_path()") == 1


def test_executor_has_single_mutation_sink_definition():
    main_source = SCRIPT.read_text()
    executor_source = (REPO / "lib/core/executor.sh").read_text()
    assert "safe_rm()" not in main_source
    assert executor_source.count("safe_rm()") == 1
    assert executor_source.count("safe_rm_contents()") == 1


def test_project_artifacts_have_single_domain_module_definition():
    main_source = SCRIPT.read_text()
    module_source = (REPO / "lib/categories/project_artifacts.sh").read_text()
    assert 'source "$SCRIPT_DIR/lib/categories/project_artifacts.sh"' in main_source
    assert "clean_project_artifacts()" not in main_source
    assert module_source.count("clean_project_artifacts()") == 1


def test_installer_artifacts_have_single_domain_module_definition():
    main_source = SCRIPT.read_text()
    module_source = (REPO / "lib/categories/installer_artifacts.sh").read_text()
    assert 'source "$SCRIPT_DIR/lib/categories/installer_artifacts.sh"' in main_source
    assert "clean_installer_artifacts()" not in main_source
    assert module_source.count("clean_installer_artifacts()") == 1
    assert "is_orphaned\\\": false" in module_source


def test_app_uninstaller_has_single_domain_module_definition():
    main_source = SCRIPT.read_text()
    module_source = (REPO / "lib/categories/app_uninstaller.sh").read_text()
    assert 'source "$SCRIPT_DIR/lib/categories/app_uninstaller.sh"' in main_source
    for function in (
        "scan_app_uninstaller",
        "clean_app_uninstaller",
        "get_app_bundle_id",
        "is_valid_app_bundle_path",
        "app_leftover_paths",
        "scan_app_uninstaller_subitems_json",
    ):
        assert f"{function}()" not in main_source
        assert module_source.count(f"{function}()") == 1


def test_mutating_owner_commands_use_the_dry_run_gateway():
    source = "\n".join(path.read_text() for path in SHELL_SOURCES)
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
