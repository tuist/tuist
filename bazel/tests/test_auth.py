"""Native auth contract tests; all identities are synthetic and HTTP stays on loopback.

Storage/locking expectations come from ServerCredentialsStore.swift,
ServerAuthenticationController.swift, CachedValueStore.swift and the Gradle
CredentialStore.kt, not from auth.py's path/lock helpers. Run with:
python -m unittest discover -s bazel/tests -p test_auth.py -v
"""

import base64
import fcntl
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PRIVATE = Path(__file__).resolve().parents[1] / "private"

# Only the public token/login entry points are called. Device tests double the
# browser and polling delay, but use the same real HTTP and filesystem as token().
CLIENT = """
import json, os, sys
sys.path.insert(0, sys.argv[1])
import auth
if os.environ.get('TEST_DEVICE'):
    auth.webbrowser.open = lambda url: print('BROWSER ' + url, flush=True)
    auth.time.sleep = lambda seconds: None
print('READY', flush=True)
try:
    if sys.argv[2] == 'token':
        result = auth.token(sys.argv[3])
    else:
        result = auth.login(sys.argv[3], *json.loads(sys.argv[4]))
    print('RESULT ' + json.dumps(result), flush=True)
except Exception as error:
    print('ERROR ' + type(error).__name__ + ': ' + str(error), flush=True)
    sys.exit(1)
"""


def jwt(**claims):
    payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return "eyJhbGciOiJub25lIn0." + payload + ".synthetic"


@contextmanager
def endpoint(respond):
    requests = []
    errors = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def handle_request(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
            media_type = self.headers.get("Content-Type", "")
            parsed = (
                urllib.parse.parse_qs(body)
                if media_type == "application/x-www-form-urlencoded"
                else json.loads(body)
                if body
                else None
            )
            record = (self.command, self.path, media_type, parsed)
            requests.append(record)
            try:
                status, value = respond(record)
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())
            except (AssertionError, OSError, ValueError) as error:
                errors.append(error)
                self.close_connection = True

        do_POST = handle_request
        do_GET = handle_request

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        if errors:
            raise AssertionError(f"Loopback server failed: {errors!r}")


class AuthTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        # Do not inherit CI flags, tokens, proxies, browsers or real user homes.
        self.env = {
            "PATH": os.defpath,
            "HOME": str(self.root / "home"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "NO_PROXY": "*",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        self.credentials = self.root / "config/tuist/credentials/127.0.0.1.json"
        self.old = {
            "accessToken": jwt(exp=1),
            "refreshToken": jwt(type="refresh", exp=4102444800),
        }
        self.fresh = jwt(exp=4102444800, sub="refreshed")
        self.pair = {
            "access_token": self.fresh,
            "refresh_token": jwt(type="refresh", exp=4102444800, generation=2),
        }

    def write(self, value, path=None):
        path = path or self.credentials
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))
        return path

    def start(self, url, operation="token", args=(), env=None):
        process = subprocess.Popen(
            [
                sys.executable,
                "-u",
                "-c",
                CLIENT,
                str(PRIVATE),
                operation,
                url,
                json.dumps(args),
            ],
            env={**self.env, **(env or {})},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        def cleanup():
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)

        self.addCleanup(cleanup)
        return process

    def finish(self, process, success=True):
        out, err = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0 if success else 1, out + err)
        self.assertEqual(err, "")
        if not success:
            self.assertRegex(out, r"ERROR (AuthenticationError|HTTPError):")
        return out

    def run_client(self, url, success=True, **kwargs):
        return self.finish(self.start(url, **kwargs), success)

    @contextmanager
    def cli_lock(self, host="127.0.0.1"):
        # CLI contract: FNV-1a UInt64 of canonical absolute credential pathname;
        # even when a legacy alias is selected, ports/case do not split the lock.
        canonical = self.credentials.with_name(host + ".json")
        digest = 0xCBF29CE484222325
        for byte in str(canonical).encode("utf-8"):
            digest = ((digest ^ byte) * 0x100000001B3) % (1 << 64)
        lock = (
            self.root
            / f"state/tuist/cached_value_store/credential-refresh-{digest:x}.lock"
        )
        lock.parent.mkdir(parents=True, exist_ok=True)
        with lock.open("w") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            try:
                yield lock
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)

    def assert_waiting(self, process):
        self.assertEqual(process.stdout.readline(), "READY\n")
        with self.assertRaises(subprocess.TimeoutExpired):
            process.wait(timeout=0.3)

    def test_environment_token_needs_no_credentials_or_exchange(self):
        with endpoint(lambda _: self.fail("Environment token must not use HTTP")) as (
            url,
            requests,
        ):
            out = self.run_client(url, env={"TUIST_TOKEN": "synthetic-project-token"})
            self.assertIn('RESULT "synthetic-project-token"', out)
            self.assertFalse(self.credentials.exists())
            self.assertEqual(requests, [])

    def test_blank_or_whitespace_environment_token_fails_closed(self):
        for supplied in ("", " ", "token\n", "two tokens"):
            with self.subTest(supplied=supplied):
                self.run_client(
                    "http://127.0.0.1:1", success=False, env={"TUIST_TOKEN": supplied}
                )

    def test_valid_cached_token_and_canonical_precedence_ignore_port(self):
        self.write({"accessToken": self.fresh})
        self.write(self.old, self.credentials.with_name("127.0.0.1..json"))
        before = self.credentials.read_bytes()
        for port in (1, 2):
            self.assertIn(self.fresh, self.run_client(f"http://127.0.0.1:{port}"))
        self.assertEqual(self.credentials.read_bytes(), before)

    def test_hostname_case_and_trailing_dot_aliases_share_credentials(self):
        alias = self.credentials.with_name("LOCALHOST..json")
        self.write({"accessToken": self.fresh}, alias)
        for url in ("https://LOCALHOST.:1", "https://localhost:2/"):
            self.assertIn(self.fresh, self.run_client(url))
        self.assertFalse(alias.with_name("localhost.json").exists())

    def test_missing_corrupt_and_rejected_credentials_never_exchange(self):
        with endpoint(lambda _: (500, {})) as (url, requests):
            self.run_client(url, success=False)
            self.assertFalse(self.credentials.exists())
            for raw in (
                b"{",
                b"null",
                b"[]",
                b"{}",
                b'{"accessToken":""}',
                json.dumps({**self.old, "rejected": True}).encode(),
            ):
                with self.subTest(raw=raw):
                    self.credentials.parent.mkdir(parents=True, exist_ok=True)
                    self.credentials.write_bytes(raw)
                    self.run_client(url, success=False)
                    self.assertEqual(self.credentials.read_bytes(), raw)
            self.assertEqual(requests, [])

    def test_expired_access_without_refresh_preserves_credentials(self):
        self.write({"accessToken": jwt(exp=1)})
        before = self.credentials.read_bytes()
        self.run_client("http://127.0.0.1:1", success=False)
        self.assertEqual(self.credentials.read_bytes(), before)

    def test_refresh_rotates_pair_atomically_with_private_permissions(self):
        self.write(self.old)
        self.credentials.chmod(0o644)
        with self.credentials.open("rb") as old_descriptor:
            before = old_descriptor.read()
            inode = os.fstat(old_descriptor.fileno()).st_ino
            with endpoint(lambda _: (200, self.pair)) as (url, requests):
                self.assertIn(self.fresh, self.run_client(url))
            self.assertEqual(
                requests,
                [
                    (
                        "POST",
                        "/api/auth/refresh_token",
                        "application/json",
                        {"refresh_token": self.old["refreshToken"]},
                    )
                ],
            )
            self.assertNotEqual(self.credentials.stat().st_ino, inode)
            old_descriptor.seek(0)
            self.assertEqual(old_descriptor.read(), before)
        self.assertEqual(stat.S_IMODE(self.credentials.stat().st_mode), 0o600)
        self.assertEqual(
            json.loads(self.credentials.read_text()),
            {"accessToken": self.fresh, "refreshToken": self.pair["refresh_token"]},
        )
        self.assertEqual(list(self.credentials.parent.iterdir()), [self.credentials])

    def test_refresh_updates_legacy_alias_without_creating_stale_duplicate(self):
        alias = self.credentials.with_name("127.0.0.1..json")
        self.write(self.old, alias)
        with endpoint(lambda _: (200, self.pair)) as (url, requests):
            self.run_client(url)
        self.assertEqual(len(requests), 1)
        self.assertEqual(json.loads(alias.read_text())["accessToken"], self.fresh)
        self.assertFalse(self.credentials.exists())

    def test_oauth_refresh_uses_issuing_client_not_environment_override(self):
        stored = {
            **self.old,
            "refreshToken": jwt(type="account", exp=4102444800),
            "oauthClientID": "issuing-client+with/reserved characters",
        }
        self.write(stored)
        with endpoint(lambda _: (200, self.pair)) as (url, requests):
            self.run_client(url, env={"TUIST_OAUTH_CLIENT_ID": "wrong-current-client"})
        self.assertEqual(
            requests,
            [
                (
                    "POST",
                    "/oauth2/token",
                    "application/x-www-form-urlencoded",
                    {
                        "grant_type": ["refresh_token"],
                        "refresh_token": [stored["refreshToken"]],
                        "client_id": [stored["oauthClientID"]],
                    },
                )
            ],
        )
        self.assertEqual(
            json.loads(self.credentials.read_text())["oauthClientID"],
            stored["oauthClientID"],
        )

    def test_http_failure_retries_but_preserves_file_byte_for_byte(self):
        self.write(self.old)
        before = self.credentials.read_bytes()
        with endpoint(lambda _: (503, {"error": "unavailable"})) as (url, requests):
            self.run_client(url, success=False)
        self.assertEqual(len(requests), 4)
        self.assertEqual(self.credentials.read_bytes(), before)

    def test_invalid_successful_refresh_response_preserves_file(self):
        for pair in (
            {},
            {"access_token": self.fresh},
            {"access_token": jwt(exp=1), "refresh_token": "synthetic"},
        ):
            with self.subTest(pair=pair):
                self.write(self.old)
                before = self.credentials.read_bytes()
                with endpoint(lambda _, pair=pair: (200, pair)) as (url, requests):
                    self.run_client(url, success=False)
                self.assertEqual(len(requests), 1)
                self.assertEqual(self.credentials.read_bytes(), before)

    def test_401_marks_rejected_and_next_process_does_not_exchange(self):
        self.write(self.old)
        with endpoint(lambda _: (401, {"error": "invalid_token"})) as (url, requests):
            self.run_client(url, success=False)
            marked = self.credentials.read_bytes()
            self.assertEqual(json.loads(marked), {**self.old, "rejected": True})
            self.run_client(url, success=False)
            self.assertEqual(len(requests), 1)
            self.assertEqual(self.credentials.read_bytes(), marked)
        self.assertEqual(stat.S_IMODE(self.credentials.stat().st_mode), 0o600)

    def test_oauth_invalid_client_preserves_but_invalid_grant_rejects(self):
        for code, rejected in (("invalid_client", False), ("invalid_grant", True)):
            with self.subTest(code=code):
                stored = {
                    **self.old,
                    "refreshToken": jwt(type="account", exp=4102444800),
                }
                self.write(stored)
                with endpoint(lambda _, code=code: (400, {"error": code})) as (
                    url,
                    requests,
                ):
                    self.run_client(url, success=False)
                self.assertEqual(len(requests), 1)
                self.assertEqual(
                    json.loads(self.credentials.read_text()),
                    {**stored, "rejected": True} if rejected else stored,
                )

    def test_cli_flock_waiter_rereads_replacement_before_exchange(self):
        alias = self.credentials.with_name("LOCALHOST..json")
        self.write(self.old, alias)
        with endpoint(lambda _: (200, self.pair)) as (url, requests):
            url = url.replace("127.0.0.1", "localhost")
            with self.cli_lock("localhost") as lock:
                inode = lock.stat().st_ino
                process = self.start(url)
                self.assert_waiting(process)
                self.assertEqual(requests, [])
                self.write({"accessToken": self.fresh}, alias)
            self.assertIn(self.fresh, self.finish(process))
            self.assertEqual(requests, [])
            self.assertEqual(
                lock.stat().st_ino, inode, "Lock inode must survive unlock"
            )

    def test_two_simultaneous_processes_exchange_refresh_only_once(self):
        self.write(self.old)
        entered, release = threading.Event(), threading.Event()

        def respond(_):
            entered.set()
            if not release.wait(8):
                raise AssertionError("Test did not release HTTP response")
            return 200, self.pair

        with endpoint(respond) as (url, requests):
            try:
                with self.cli_lock():
                    first, second = self.start(url), self.start(url)
                    self.assert_waiting(first)
                    self.assert_waiting(second)
                    self.assertEqual(requests, [])
                self.assertTrue(entered.wait(5))
                with self.assertRaises(subprocess.TimeoutExpired):
                    second.wait(timeout=0.3)
                release.set()
                self.assertIn(self.fresh, self.finish(first))
                self.assertIn(self.fresh, self.finish(second))
                self.assertEqual(len(requests), 1)
            finally:
                release.set()

    def test_session_changed_during_http_cannot_be_overwritten_or_resurrected(self):
        for status in (200, 401):
            for change in ("replace", "delete"):
                with self.subTest(status=status, change=change):
                    self.write(self.old)
                    entered, release = threading.Event(), threading.Event()

                    def respond(_, entered=entered, release=release, status=status):
                        entered.set()
                        if not release.wait(8):
                            raise AssertionError("Test did not release HTTP response")
                        return status, self.pair if status == 200 else {
                            "error": "invalid_token"
                        }

                    with endpoint(respond) as (url, requests):
                        try:
                            process = self.start(url)
                            self.assertTrue(entered.wait(5))
                            if change == "replace":
                                replacement = {
                                    "accessToken": jwt(exp=4102444800, sub="new-login")
                                }
                                self.write(replacement)
                                expected = self.credentials.read_bytes()
                            else:
                                self.credentials.unlink()
                            release.set()
                            self.finish(process, success=False)
                            self.assertEqual(len(requests), 1)
                            if change == "replace":
                                self.assertEqual(
                                    self.credentials.read_bytes(), expected
                                )
                            else:
                                self.assertFalse(self.credentials.exists())
                        finally:
                            release.set()

    def test_password_login_replaces_corrupt_credentials_and_stores_private_pair(self):
        self.credentials.parent.mkdir(parents=True)
        self.credentials.write_text("corrupt old session")
        with endpoint(lambda _: (200, self.pair)) as (url, requests):
            self.run_client(
                url,
                operation="login",
                args=("person@example.invalid", "synthetic-password"),
            )
            self.assertIn(self.fresh, self.run_client(url))
        self.assertEqual(
            requests,
            [
                (
                    "POST",
                    "/api/auth",
                    "application/json",
                    {
                        "email": "person@example.invalid",
                        "password": "synthetic-password",
                    },
                )
            ],
        )
        self.assertEqual(
            json.loads(self.credentials.read_text()),
            {"accessToken": self.fresh, "refreshToken": self.pair["refresh_token"]},
        )
        self.assertEqual(stat.S_IMODE(self.credentials.stat().st_mode), 0o600)

    def test_failed_login_preserves_existing_credentials(self):
        self.write(self.old)
        before = self.credentials.read_bytes()
        with endpoint(lambda _: (401, {})) as (url, requests):
            self.run_client(
                url,
                operation="login",
                args=("person@example.invalid", "synthetic"),
                success=False,
            )
        self.assertEqual(len(requests), 1)
        self.assertEqual(self.credentials.read_bytes(), before)

    def test_ci_oidc_login_exchanges_identity_and_account_selector(self):
        with endpoint(lambda _: (200, {"access_token": self.fresh})) as (url, requests):
            self.run_client(
                url,
                operation="login",
                env={
                    "CI": "true",
                    "TUIST_OIDC_TOKEN": " synthetic-workload-identity ",
                    "TUIST_OIDC_ACCOUNT": " example-account ",
                },
            )
        self.assertEqual(
            requests,
            [
                (
                    "POST",
                    "/api/auth/oidc/token",
                    "application/json",
                    {
                        "token": "synthetic-workload-identity",
                        "account_handle": "example-account",
                    },
                )
            ],
        )
        self.assertEqual(
            json.loads(self.credentials.read_text()), {"accessToken": self.fresh}
        )

    def test_ci_without_workload_identity_does_not_open_browser_or_write_credentials(
        self,
    ):
        with endpoint(lambda _: (200, self.pair)) as (url, requests):
            self.run_client(url, operation="login", success=False, env={"CI": "true"})
        self.assertEqual(requests, [])
        self.assertFalse(self.credentials.exists())

    def test_device_login_polls_pending_then_saves_tokens(self):
        count = 0

        def respond(_):
            nonlocal count
            count += 1
            return (202, {}) if count == 1 else (200, self.pair)

        with endpoint(respond) as (url, requests):
            out = self.run_client(url, operation="login", env={"TEST_DEVICE": "1"})
        self.assertEqual(len(requests), 2)
        self.assertEqual(requests[0], requests[1])
        method, path, _, body = requests[0]
        self.assertEqual(method, "GET")
        self.assertTrue(path.startswith("/api/auth/device_code/"))
        self.assertIsNone(body)
        code = path.rsplit("/", 1)[1]
        self.assertIn(f"BROWSER {url}/auth/device_codes/{code}?type=cli", out)
        self.assertEqual(
            json.loads(self.credentials.read_text())["accessToken"], self.fresh
        )


if __name__ == "__main__":
    unittest.main()
