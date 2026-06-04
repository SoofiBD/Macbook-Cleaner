"""Unit tests for server.py input validation helpers."""
import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'web'))


class TestValidateAppLeftover(unittest.TestCase):
    def setUp(self):
        from server import _validate_app_leftover
        self.v = _validate_app_leftover

    def test_allows_simple_name(self):
        self.assertTrue(self.v("Slack"))
        self.assertTrue(self.v("com.google.Chrome"))
        self.assertTrue(self.v("My App"))
        self.assertTrue(self.v("App-Name.1"))

    def test_blocks_path_traversal(self):
        self.assertFalse(self.v("../etc/passwd"))
        self.assertFalse(self.v("/absolute/path"))

    def test_blocks_special_chars(self):
        self.assertFalse(self.v("app;rm -rf /"))
        self.assertFalse(self.v("app`id`"))
        self.assertFalse(self.v("app$HOME"))

    def test_blocks_too_long(self):
        self.assertFalse(self.v("a" * 65))

    def test_blocks_empty(self):
        self.assertFalse(self.v(""))


class TestValidateDeveloperItem(unittest.TestCase):
    def setUp(self):
        from server import _validate_developer_item
        self.v = _validate_developer_item

    def test_whitelist_entries(self):
        for item in ("derived_data", "broken_links", "brew_cache",
                     "docker_prune", "npm_cache", "pip_cache"):
            self.assertTrue(self.v(item), f"Expected True for {item}")

    def test_rejects_unknown(self):
        self.assertFalse(self.v("evil_cmd"))
        self.assertFalse(self.v("../../etc"))
        self.assertFalse(self.v("; rm -rf /"))

    def test_new_developer_keys_allowed(self):
        for k in ["device_support", "coresim_caches", "xcode_archives",
                  "simctl_unavailable", "pnpm_cache", "yarn_cache",
                  "cocoapods_cache", "gradle_cache", "maven_repo"]:
            self.assertTrue(self.v(k), k)


class TestValidateBrowserKey(unittest.TestCase):
    def setUp(self):
        from server import _validate_browser_key
        self.v = _validate_browser_key

    def test_whitelist_entries(self):
        for k in ("safari", "cookies", "chrome", "firefox",
                  "brave", "edge", "opera", "arc"):
            self.assertTrue(self.v(k), f"Expected True for {k}")

    def test_rejects_unknown(self):
        self.assertFalse(self.v("not_a_browser"))
        self.assertFalse(self.v("; rm -rf /"))


class TestValidateAppName(unittest.TestCase):
    def setUp(self):
        from server import _validate_app_name
        self.v = _validate_app_name

    def test_allows_valid_app_names(self):
        self.assertTrue(self.v("Firefox"))
        self.assertTrue(self.v("Visual Studio Code"))
        self.assertTrue(self.v("App-Name.1"))

    def test_blocks_traversal(self):
        self.assertFalse(self.v("../Applications"))
        self.assertFalse(self.v("/Applications/Evil"))

    def test_blocks_injection(self):
        self.assertFalse(self.v("App;rm -rf /"))
        self.assertFalse(self.v("App`id`"))

    def test_blocks_empty(self):
        self.assertFalse(self.v(""))


if __name__ == "__main__":
    unittest.main()
