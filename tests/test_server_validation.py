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
                  "cocoapods_cache", "gradle_cache", "maven_repo",
                  "xcode_products", "simulator_logs", "simulator_devices",
                  "font_caches", "brew_cleanup", "swift_pm_cache", "xcode_logs"]:
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


class TestValidateBrewName(unittest.TestCase):
    def setUp(self):
        from server import _validate_brew_name
        self.v = _validate_brew_name

    def test_allows_valid_tokens(self):
        self.assertTrue(self.v("wget"))
        self.assertTrue(self.v("google-chrome"))
        self.assertTrue(self.v("python@3.12"))
        self.assertTrue(self.v("homebrew/cask/firefox"))

    def test_blocks_flag_injection(self):
        # A leading dash would let brew parse the token as an option.
        self.assertFalse(self.v("--force"))
        self.assertFalse(self.v("-q"))

    def test_blocks_traversal_and_injection(self):
        self.assertFalse(self.v("../etc"))
        self.assertFalse(self.v("pkg;rm -rf /"))
        self.assertFalse(self.v("pkg`id`"))
        self.assertFalse(self.v(""))


class TestValidateProjectArtifact(unittest.TestCase):
    def setUp(self):
        from server import _validate_project_artifact
        self.v = _validate_project_artifact

    def test_allows_recognized_artifacts(self):
        self.assertTrue(self.v("/Users/x/Code/app/node_modules"))
        self.assertTrue(self.v("/Users/x/Developer/cli/target"))
        self.assertTrue(self.v("/Users/x/Projects/pkg/.build"))
        self.assertTrue(self.v("/Users/x/repos/svc/vendor"))
        self.assertTrue(self.v("/Users/x/src/app/.dart_tool"))

    def test_blocks_traversal(self):
        self.assertFalse(self.v("/Users/x/../../etc/node_modules"))

    def test_blocks_non_artifact_basename(self):
        self.assertFalse(self.v("/Users/x/Documents"))
        self.assertFalse(self.v("/etc"))
        self.assertFalse(self.v("/Users/x/Code/app/src"))

    def test_blocks_relative_and_nonstring(self):
        self.assertFalse(self.v("node_modules"))
        self.assertFalse(self.v(""))
        self.assertFalse(self.v(None))


class TestDeveloperWhitelistSync(unittest.TestCase):
    """The shell and server developer-key whitelists must stay identical."""

    def test_whitelists_match(self):
        import re
        from server import _DEVELOPER_WHITELIST

        script = os.path.join(os.path.dirname(__file__), '..', 'clean_mac.sh')
        with open(script, encoding='utf-8') as f:
            text = f.read()

        m = re.search(r'_VALID_DEVELOPER_KEYS="([^"]*)"', text)
        self.assertIsNotNone(m, "_VALID_DEVELOPER_KEYS not found in clean_mac.sh")
        shell_keys = set(m.group(1).split('|'))

        self.assertEqual(
            shell_keys, set(_DEVELOPER_WHITELIST),
            "clean_mac.sh _VALID_DEVELOPER_KEYS and server _DEVELOPER_WHITELIST "
            "have drifted out of sync",
        )


class TestAllowedHost(unittest.TestCase):
    def setUp(self):
        from server import _is_allowed_host
        self.v = _is_allowed_host

    def test_allows_loopback(self):
        self.assertTrue(self.v("localhost"))
        self.assertTrue(self.v("localhost:8080"))
        self.assertTrue(self.v("127.0.0.1"))
        self.assertTrue(self.v("127.0.0.1:8080"))
        self.assertTrue(self.v("[::1]"))
        self.assertTrue(self.v("[::1]:8080"))

    def test_blocks_external_hosts(self):
        self.assertFalse(self.v("example.com"))
        self.assertFalse(self.v("192.168.1.20:8080"))
        self.assertFalse(self.v("evil.attacker.test"))

    def test_blocks_empty(self):
        self.assertFalse(self.v(""))


class TestAllowedOrigin(unittest.TestCase):
    def setUp(self):
        from server import _is_allowed_origin
        self.v = _is_allowed_origin

    def test_absent_origin_allowed(self):
        # curl / native clients omit Origin; allowed (token + Host still guard)
        self.assertTrue(self.v(None))
        self.assertTrue(self.v(""))

    def test_loopback_origin_allowed(self):
        self.assertTrue(self.v("http://localhost:8080"))
        self.assertTrue(self.v("http://127.0.0.1:8080"))
        self.assertTrue(self.v("http://[::1]:8080"))

    def test_external_origin_blocked(self):
        self.assertFalse(self.v("http://evil.example.com"))
        self.assertFalse(self.v("https://attacker.test"))
        self.assertFalse(self.v("null"))


class TestComputeForecast(unittest.TestCase):
    def setUp(self):
        from server import compute_forecast
        self.f = compute_forecast

    def test_insufficient_data(self):
        r = self.f([], 1000, 500)
        self.assertIsNone(r["days_until_full"])
        self.assertEqual(r["history_points"], 0)
        r = self.f([(0.0, 100)], 1000, 500)
        self.assertIsNone(r["days_until_full"])

    def test_steady_growth_predicts_full(self):
        day = 86400
        total = 1000
        # 10 bytes/day growth, currently at 900 → 100 remaining → ~10 days
        hist = [(i * day, 800 + i * 10) for i in range(11)]  # 10 days span
        r = self.f(hist, total, 900)
        self.assertEqual(r["daily_growth_bytes"], 10)
        self.assertEqual(r["days_until_full"], 10)
        self.assertGreaterEqual(r["history_span_days"], 10)

    def test_shrinking_usage_no_forecast(self):
        day = 86400
        hist = [(i * day, 900 - i * 10) for i in range(11)]
        r = self.f(hist, 1000, 800)
        self.assertIsNone(r["days_until_full"])
        self.assertLessEqual(r["daily_growth_bytes"], 0)

    def test_span_under_one_day_no_forecast(self):
        hist = [(0.0, 100), (3600.0, 200)]  # 1 hour apart
        r = self.f(hist, 1000, 500)
        self.assertIsNone(r["days_until_full"])

    def test_beyond_horizon_returns_none(self):
        day = 86400
        # 1 byte/day growth, 10000 remaining → 10000 days > 365 → None
        hist = [(i * day, 100 + i) for i in range(11)]
        r = self.f(hist, 100000, 90000)
        self.assertIsNone(r["days_until_full"])
        self.assertEqual(r["daily_growth_bytes"], 1)


class TestRecordSnapshot(unittest.TestCase):
    def setUp(self):
        from server import _record_snapshot
        self.f = _record_snapshot

    def test_appends_when_empty(self):
        out = self.f([], 500, now=1000.0)
        self.assertEqual(out, [(1000.0, 500)])

    def test_throttles_within_interval(self):
        hist = [(1000.0, 500)]
        out = self.f(hist, 600, now=1000.0 + 1800)  # 30 min later
        self.assertEqual(out, hist)  # unchanged

    def test_appends_after_interval(self):
        hist = [(1000.0, 500)]
        out = self.f(hist, 600, now=1000.0 + 7200)  # 2 hours later
        self.assertEqual(len(out), 2)
        self.assertEqual(out[-1], (1000.0 + 7200, 600))

    def test_prunes_old_entries(self):
        now = 100 * 86400.0
        hist = [(0.0, 100), (95 * 86400.0, 200)]  # first is >90 days old
        out = self.f(hist, 300, now=now)
        self.assertTrue(all(t > now - 90 * 86400 for t, _ in out))
        self.assertNotIn((0.0, 100), out)


class TestExtraEnvForClean(unittest.TestCase):
    def setUp(self):
        from server import _extra_env_for_clean
        self.f = _extra_env_for_clean

    def test_dry_run_true_sets_env(self):
        self.assertEqual(self.f({"dry_run": True}),
                         {"APPLE_CLEANUP_DRYRUN": "1"})

    def test_dry_run_absent_or_false_empty(self):
        self.assertEqual(self.f({}), {})
        self.assertEqual(self.f({"dry_run": False}), {})
        # Only a real boolean True enables it (no truthy strings)
        self.assertEqual(self.f({"dry_run": "true"}), {})
        self.assertEqual(self.f({"dry_run": 1}), {})


class TestTokenCompare(unittest.TestCase):
    def setUp(self):
        from server import _token_matches, SESSION_TOKEN
        self.v = _token_matches
        self.token = SESSION_TOKEN

    def test_matches_correct_token(self):
        self.assertTrue(self.v(self.token))

    def test_rejects_wrong_token(self):
        self.assertFalse(self.v("wrong"))
        self.assertFalse(self.v(None))
        self.assertFalse(self.v(""))


if __name__ == "__main__":
    unittest.main()


class TestHistoryRoute(unittest.TestCase):
    """GET /api/history shells out to clean_mac.sh --history-json and returns a list."""

    def test_history_route_returns_list(self):
        import http.client
        import http.server
        import json as _json
        import os
        import tempfile
        import threading
        import importlib.util

        # Load the server module by path.
        web_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "web")
        spec = importlib.util.spec_from_file_location(
            "cleanup_server", os.path.join(web_dir, "server.py"))
        server = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(server)

        home = tempfile.mkdtemp()
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = home  # isolated => empty history => []
        httpd = http.server.HTTPServer(("127.0.0.1", 0), server.CleanupHandler)
        port = httpd.server_address[1]
        t = threading.Thread(target=httpd.serve_forever, daemon=True)
        t.start()
        try:
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=20)
            conn.request("GET", "/api/history", headers={"Host": f"127.0.0.1:{port}"})
            resp = conn.getresponse()
            body = resp.read().decode()
            self.assertEqual(resp.status, 200, body)
            self.assertIsInstance(_json.loads(body), list)
        finally:
            httpd.shutdown()
            if old_home is not None:
                os.environ["HOME"] = old_home


class TestValidateSessionId(unittest.TestCase):
    def setUp(self):
        from server import _validate_session_id
        self.v = _validate_session_id

    def test_allows_uuid(self):
        self.assertTrue(self.v("3F2504E0-4F89-41D3-9A0C-0305E82C3301"))

    def test_allows_pid_ts_fallback(self):
        self.assertTrue(self.v("12345-1700000000"))

    def test_blocks_injection(self):
        self.assertFalse(self.v("; rm -rf /"))
        self.assertFalse(self.v("../../etc"))
        self.assertFalse(self.v(""))
        self.assertFalse(self.v("a" * 50))


class TestValidateItemIds(unittest.TestCase):
    def setUp(self):
        from server import _validate_item_ids
        self.v = _validate_item_ids

    def test_allows_int_list(self):
        self.assertTrue(self.v([1, 2, 3]))

    def test_blocks_non_int(self):
        self.assertFalse(self.v(["1; rm"]))
        self.assertFalse(self.v([-1]))
        self.assertFalse(self.v([]))
        self.assertFalse(self.v("notalist"))
