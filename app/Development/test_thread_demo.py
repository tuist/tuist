"""Run: /usr/bin/python3 -B -m unittest discover -s app/Development -v.

No authenticated inference, network cloning, or user checkout is used. Sandbox
tests intentionally run the real Apple Python/sandbox-exec and fail closed on Mac.
All disposable repositories, canaries, and databases are removed by TemporaryDirectory.
"""

import http.client
import json
import os
from pathlib import Path
import socket
import sqlite3
import stat
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

import thread_demo as demo


CORRECT = "def calculate_total(items):\n    return sum(price * quantity for price, quantity in items)\n"


def action(kind, path="", content="", message=""):
    return {"kind": kind, "path": path, "content": content, "message": message}


def request(goal=demo.GOAL):
    return {"goal": goal, "profile": "macos", "request_id": str(uuid.uuid4())}


class ScriptedInference:
    def __init__(self, actions):
        self.actions = iter(actions)
        self.prompts = []

    def __call__(self, prompt):
        self.prompts.append(prompt)
        return next(self.actions)


@unittest.skipUnless(sys.platform == "darwin", "Real macOS sandbox required")
class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="tuist-thread-demo-test-")
        self.root = Path(self.temporary.name).resolve()
        self.inference = ScriptedInference([])
        self.backend = demo.Backend(self.root, self.inference, start_worker=False)

    def tearDown(self):
        if self.backend is not None:
            self.backend.close()
        self.temporary.cleanup()

    def restart(self, inference=None, worker=False):
        self.backend.close()
        self.backend = None
        self.backend = demo.Backend(self.root, inference or self.inference, start_worker=worker)

    def run_actions(self, thread_id, actions):
        self.inference = ScriptedInference(actions)
        self.backend.inference = self.inference
        for _ in actions:
            self.backend._step(thread_id)
        return self.backend.get(thread_id)

    def wait_terminal(self, thread_id):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            thread = self.backend.get(thread_id)
            if thread["status"] not in ("queued", "running"):
                return thread
            time.sleep(0.02)
        self.fail("Worker did not finish")

    def test_asymmetric_fixture_fails_then_corrected_tests_pass(self):
        thread = self.backend.create(request())
        workspace = self.backend.workspaces / thread["id"]
        self.assertFalse(self.backend.sandbox.test(workspace))
        thread = self.run_actions(thread["id"], [
            action("read", "test_totals.py"),
            action("write", "totals.py", CORRECT),
            action("test"), action("finish", message="Quantities fixed; all three tests passed."),
        ])
        self.assertEqual(thread["status"], "completed")
        self.assertIn("+    return sum(price * quantity", thread["diff"])
        self.assertIn("Fixed tests: 3 passed", [message["content"] for message in thread["messages"]])
        self.assertEqual(thread["messages"][-1]["role"], "assistant")
        self.assertEqual((workspace / "test_totals.py").read_text(), demo.FIXTURE["test_totals.py"])
        self.assertIn("41", demo.FIXTURE["test_totals.py"])
        self.assertIn("30", demo.FIXTURE["test_totals.py"])

    def test_finish_without_tests_is_not_completion(self):
        thread = self.backend.create(request())
        thread = self.run_actions(thread["id"], [action("finish", message="All tests pass!")])
        self.assertEqual(thread["status"], "failed")
        self.assertNotIn("All tests pass!", json.dumps(thread))

    def test_failed_tests_are_not_completion(self):
        thread = self.backend.create(request())
        thread = self.run_actions(thread["id"], [action("test"), action("finish")])
        self.assertEqual(thread["status"], "failed")
        self.assertIn("Fixed tests failed", json.dumps(thread))

    def test_write_after_passing_test_requires_new_test(self):
        thread = self.backend.create(request())
        thread = self.run_actions(thread["id"], [
            action("write", "totals.py", CORRECT), action("test"),
            action("write", "totals.py", CORRECT + "\n"), action("finish"),
        ])
        self.assertEqual(thread["status"], "failed")

    def test_rename_metadata_preserves_goal_branch_worktree_and_test_evidence(self):
        thread = self.backend.create(request())
        thread_id = thread["id"]
        branch = thread["branch"]
        self.assertEqual(thread["title"], "New thread")
        workspace = self.backend.workspaces / thread_id
        thread = self.run_actions(thread_id, [
            action("write", "totals.py", CORRECT), action("test"),
        ])
        before = dict(self.backend._row(thread_id))
        files = {name: (workspace / name).read_bytes() for name in demo.FIXTURE}
        with patch.object(self.backend.sandbox, "test", side_effect=AssertionError("Must not execute")):
            thread = self.run_actions(thread_id, [action("set_thread_name", content="  Quantity totals  ")])
        self.assertEqual(thread["title"], "Quantity totals")
        self.assertEqual(thread["goal"], demo.GOAL)
        self.assertEqual(thread["branch"], branch)
        self.assertEqual(self.backend._row(thread_id)["tested_revision"], before["tested_revision"])
        self.assertEqual(self.backend._row(thread_id)["revision"], before["revision"])
        self.assertEqual(files, {name: (workspace / name).read_bytes() for name in demo.FIXTURE})
        self.restart()
        thread = self.backend.get(thread_id)
        self.assertEqual(thread["title"], "Quantity totals")
        self.assertEqual(thread["goal"], demo.GOAL)
        self.assertEqual(thread["branch"], branch)
        thread = self.run_actions(thread_id, [action("finish", message="Done")])
        self.assertEqual(thread["status"], "completed")
        turn = {"content": "Check the same fix again", "request_id": str(uuid.uuid4())}
        self.backend.add_message(thread_id, turn)
        thread = self.run_actions(thread_id, [action("test"), action("finish", message="Still passes")])
        self.assertEqual(thread["status"], "completed")
        self.assertEqual(thread["goal"], demo.GOAL)
        self.assertEqual(thread["branch"], branch)
        self.assertIn(demo.GOAL, self.inference.prompts[0])
        self.assertIn(turn["content"], self.inference.prompts[0])

    def test_two_threads_are_distinct_git_worktrees(self):
        first = self.backend.create(request())
        second = self.backend.create(request())
        self.assertNotEqual(first["branch"], second["branch"])
        for thread in (first, second):
            self.assertEqual(thread["branch"], "code/" + thread["id"])
            path = self.backend.workspaces / thread["id"]
            self.assertTrue((path / ".git").is_file())
            listing = self.backend._git(["worktree", "list", "--porcelain"])
            self.assertIn("worktree " + str(path), listing)
            self.assertIn("branch refs/heads/" + thread["branch"], listing)
        self.run_actions(first["id"], [action("write", "totals.py", CORRECT)])
        self.assertEqual(self.backend._file(second["id"], "totals.py"), demo.FIXTURE["totals.py"])

    def test_duplicate_create_and_turn_do_not_duplicate_actions(self):
        body = request()
        thread = self.backend.create(body)
        self.assertEqual(self.backend.create(body)["id"], thread["id"])
        self.assertEqual(len(self.backend.list_threads()["threads"]), 1)
        self.run_actions(thread["id"], [action("finish")])
        turn = {"content": "Try again", "request_id": str(uuid.uuid4())}
        self.backend.add_message(thread["id"], turn)
        self.backend.add_message(thread["id"], turn)
        self.run_actions(thread["id"], [action("finish")])
        self.backend.add_message(thread["id"], turn)
        thread = self.backend.get(thread["id"])
        self.assertEqual([message["content"] for message in thread["messages"] if message["role"] == "user"],
                         [demo.GOAL, "Try again"])
        counts = self.backend.db.execute("SELECT kind,COUNT(*) FROM actions GROUP BY kind").fetchall()
        self.assertEqual({row[0]: row[1] for row in counts}, {"create_worktree": 1, "inference": 2, "finish": 2})
        self.assertEqual(thread["status"], "failed")
        with self.assertRaises(demo.SafeError):
            self.backend.create(dict(body, goal="different"))
        with self.assertRaises(demo.SafeError):
            self.backend.add_message(thread["id"], dict(turn, content="different"))

    def test_restart_queued_thread_and_pending_inference_recover(self):
        queued = self.backend.create(request())
        pending = self.backend.create(request())
        with self.backend.db:
            self.backend.db.execute("UPDATE threads SET status='running' WHERE id=?", (pending["id"],))
            pending_id = self.backend._admit_inference(pending["id"])
        inference = ScriptedInference([action("finish"), action("finish")])
        self.restart(inference, worker=True)
        self.assertEqual(self.wait_terminal(queued["id"])["status"], "failed")
        self.assertEqual(self.wait_terminal(pending["id"])["status"], "failed")
        with self.backend.lock:
            row = self.backend.db.execute("SELECT state FROM actions WHERE id=?", (pending_id,)).fetchone()
            count = self.backend.db.execute("SELECT COUNT(*) FROM actions WHERE thread_id=? AND kind='inference'",
                                             (pending["id"],)).fetchone()[0]
        self.assertEqual(row[0], "completed")
        self.assertEqual(count, 1)
        self.assertEqual(len(inference.prompts), 2)

    def test_restart_executing_write_is_unknown_never_replayed(self):
        thread = self.backend.create(request())
        thread_id = thread["id"]
        with self.backend.db:
            self.backend.db.execute("UPDATE threads SET status='running' WHERE id=?", (thread_id,))
            self.backend.db.execute("INSERT INTO actions(thread_id,kind,state,payload) VALUES(?,'write','executing',?)",
                                    (thread_id, json.dumps(action("write", "totals.py", CORRECT))))
        self.backend._file(thread_id, "totals.py", "# partial side effect\n")
        inference = ScriptedInference([action("write", "totals.py", CORRECT)])
        self.restart(inference, worker=True)
        self.assertEqual(self.backend.get(thread_id)["status"], "outcome_unknown")
        time.sleep(0.1)
        self.assertEqual(inference.prompts, [])
        self.assertEqual(self.backend._file(thread_id, "totals.py"), "# partial side effect\n")
        with self.assertRaises(demo.SafeError):
            self.backend.add_message(thread_id, {"content": "retry", "request_id": str(uuid.uuid4())})
        with self.backend.lock:
            self.assertEqual(self.backend.db.execute("SELECT state FROM actions WHERE kind='write'").fetchone()[0],
                             "outcome_unknown")

    def test_worktree_creation_failure_is_idempotent_unknown(self):
        body = request()
        with patch.object(self.backend, "_git", side_effect=OSError("PRIVATE_PROVIDER_ERROR")):
            thread = self.backend.create(body)
        self.assertEqual(thread["status"], "outcome_unknown")
        self.assertEqual(self.backend.create(body)["id"], thread["id"])
        self.restart()
        self.assertEqual(self.backend.get(thread["id"])["status"], "outcome_unknown")
        self.assertNotIn("PRIVATE_PROVIDER_ERROR", (self.root / "threads.sqlite3").read_bytes().decode("latin1"))

    def test_action_admission_is_committed_before_execution(self):
        thread = self.backend.create(request())
        original = self.backend._file

        def checked(thread_id, name, write=None):
            if write is not None:
                with sqlite3.connect(self.root / "threads.sqlite3") as other:
                    row = other.execute("SELECT state FROM actions WHERE kind='write'").fetchone()
                    self.assertEqual(row[0], "executing")
            return original(thread_id, name, write)

        with patch.object(self.backend, "_file", side_effect=checked):
            self.run_actions(thread["id"], [action("write", "totals.py", CORRECT)])
        self.assertEqual(self.backend.db.execute("SELECT state FROM actions WHERE kind='write'").fetchone()[0], "completed")

    def test_invalid_path_and_test_writes_rejected_before_admission(self):
        thread = self.backend.create(request())
        for bad in (action("read", "../outside"), action("write", "/tmp/evil", "x"),
                    action("write", "test_totals.py", "x")):
            with self.subTest(bad=bad):
                with self.assertRaises(demo.SafeError):
                    demo.validate_action(bad)
        thread = self.run_actions(thread["id"], [action("write", "../outside", "x")])
        self.assertEqual(thread["status"], "failed")
        self.assertEqual(self.backend.db.execute("SELECT COUNT(*) FROM actions WHERE kind='write'").fetchone()[0], 0)

    def test_symlinks_and_hardlinks_are_not_followed(self):
        thread = self.backend.create(request())
        outside = self.root / "outside"
        outside.write_text("canary")
        path = self.backend.workspaces / thread["id"] / "totals.py"
        path.unlink()
        path.symlink_to(outside)
        with self.assertRaises((demo.SafeError, OSError)):
            self.backend._file(thread["id"], "totals.py", CORRECT)
        path.unlink()
        os.link(outside, path)
        with self.assertRaises(demo.SafeError):
            self.backend._file(thread["id"], "totals.py", CORRECT)
        self.assertEqual(outside.read_text(), "canary")

    def test_action_loop_is_bounded(self):
        thread = self.backend.create(request())
        self.inference = ScriptedInference([action("read", "totals.py")] * (demo.MAX_ACTIONS + 1))
        self.backend.inference = self.inference
        for _ in range(demo.MAX_ACTIONS + 1):
            self.backend._step(thread["id"])
        self.assertEqual(self.backend.get(thread["id"])["status"], "failed")
        self.assertEqual(len(self.inference.prompts), demo.MAX_ACTIONS)

    def test_private_permissions_and_single_server(self):
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.root / "threads.sqlite3").stat().st_mode), 0o600)
        with self.assertRaises(demo.SafeError):
            demo.Backend(self.root, self.inference, start_worker=False)

    def test_request_validation_and_busy_rejection(self):
        for body in (dict(request(), profile="linux"), dict(request(), visibility="public"),
                     request("é" * 2001), request(" "), dict(request(), request_id="bad")):
            with self.subTest(body=body):
                with self.assertRaises(demo.SafeError):
                    self.backend.create(body)
        thread = self.backend.create(request("é" * 2000))
        with self.assertRaises(demo.SafeError):
            self.backend.add_message(thread["id"], {"content": "busy", "request_id": str(uuid.uuid4())})
        with self.assertRaises(demo.SafeError):
            self.backend.get(str(uuid.uuid4()))

    def test_sandbox_canary_home_network_write_and_environment(self):
        workspace = self.root / "sandbox-check"
        workspace.mkdir()
        with tempfile.TemporaryDirectory(prefix="thread-demo-canary-", dir=Path.home()) as outside:
            canary = Path(outside) / "fake-provider-credential"
            canary.write_text("synthetic-canary")
            code = '''import os, socket
from pathlib import Path
assert set(os.environ) <= {"HOME", "PATH", "LANG", "LC_CTYPE", "__CF_USER_TEXT_ENCODING"}
assert "ANTHROPIC_API_KEY" not in os.environ
try:
    Path(CANARY).read_text()
except PermissionError:
    pass
else:
    raise SystemExit(2)
try:
    Path("not-allowed").write_text("x")
except PermissionError:
    pass
else:
    raise SystemExit(3)
try:
    socket.socket().connect(("127.0.0.1", 9))
except PermissionError:
    pass
else:
    raise SystemExit(4)
print("ISOLATED")
'''.replace("CANARY", repr(str(canary)))
            with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "synthetic-must-not-inherit"}):
                result, output = self.backend.sandbox.run(workspace, ["-c", code])
            self.assertEqual((result, output), (0, b"ISOLATED\n"))

    def test_sandbox_verification_fails_closed(self):
        with patch.object(demo.Sandbox, "run", return_value=(0, b"outside-canary-readable")):
            with self.assertRaises(demo.SafeError):
                demo.Sandbox(self.root)

    def test_inference_exception_diagnostics_never_enter_thread_or_journal(self):
        thread = self.backend.create(request())
        self.backend.inference = lambda _: (_ for _ in ()).throw(RuntimeError("PRIVATE_PROVIDER_ERROR"))
        self.backend._step(thread["id"])
        thread = self.backend.get(thread["id"])
        self.assertEqual(thread["status"], "failed")
        self.assertNotIn("PRIVATE_PROVIDER_ERROR", json.dumps(thread))
        self.assertNotIn(b"PRIVATE_PROVIDER_ERROR", (self.root / "threads.sqlite3").read_bytes())

    def test_worker_survives_phone_disconnection_over_real_http(self):
        entered = threading.Event()
        release = threading.Event()

        def inference(prompt):
            entered.set()
            release.wait(5)
            return action("finish", message="Not a real success")

        self.restart(inference, worker=True)
        server = demo.LocalServer(self.backend, 0)
        serving = threading.Thread(target=server.serve_forever)
        serving.start()
        try:
            body = json.dumps(request()).encode()
            client = socket.create_connection(server.server_address)
            client.sendall(("POST /threads HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n"
                            "Content-Type: application/json\r\nContent-Length: %d\r\n\r\n" %
                            (server.server_port, len(body))).encode() + body)
            client.close()
            self.assertTrue(entered.wait(5))
            release.set()
            threads = self.backend.list_threads()["threads"]
            self.assertEqual(len(threads), 1)
            thread = self.wait_terminal(threads[0]["id"])
            self.assertEqual(thread["status"], "failed")
            connection = http.client.HTTPConnection(*server.server_address, timeout=5)
            connection.request("GET", "/threads")
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(json.loads(response.read())["threads"][0]["id"], thread["id"])
            connection.close()
        finally:
            release.set()
            server.shutdown()
            server.server_close()
            serving.join()

    def test_http_contract_and_reject_external_origin_host_and_invalid_body(self):
        server = demo.LocalServer(self.backend, 0)
        serving = threading.Thread(target=server.serve_forever)
        serving.start()

        def call(method, path, body=None, headers=None):
            connection = http.client.HTTPConnection(*server.server_address, timeout=5)
            connection.request(method, path, body, headers or {})
            response = connection.getresponse()
            value = json.loads(response.read())
            self.assertIsNone(response.getheader("Access-Control-Allow-Origin"))
            connection.close()
            return response.status, value

        try:
            self.assertEqual(server.server_address[0], "127.0.0.1")
            self.assertEqual(call("GET", "/threads"), (200, {"threads": []}))
            status, thread = call("POST", "/threads", json.dumps(request()), {"Content-Type": "application/json"})
            self.assertEqual(status, 200)
            self.assertEqual(set(thread), {"id", "title", "goal", "branch", "repository", "profile",
                                            "status", "visibility", "messages", "diff"})
            self.assertEqual(call("GET", "/threads/" + thread["id"]), (200, thread))
            self.assertEqual(call("POST", "/threads/" + thread["id"] + "/messages",
                                  json.dumps({"content": "busy", "request_id": str(uuid.uuid4())}),
                                  {"Content-Type": "application/json"})[0], 409)
            self.assertEqual(call("GET", "/threads", headers={"Origin": "https://example.com"})[0], 403)
            self.assertEqual(call("GET", "/threads", headers={"Host": "attacker.example"})[0], 403)
            self.assertEqual(call("POST", "/threads", "{}", {"Content-Type": "text/plain"})[0], 400)
            self.assertEqual(call("POST", "/threads", '{"goal":"x","goal":"y"}',
                                  {"Content-Type": "application/json"})[0], 400)
            self.assertEqual(call("GET", "/threads/../../secret")[0], 404)
        finally:
            server.shutdown()
            server.server_close()
            serving.join()


class ValidationTests(unittest.TestCase):
    def test_thread_names_valid_trimmed_unicode_and_invalid(self):
        self.assertEqual(demo.validate_action(action("set_thread_name", content="  Fix quantities  "))["content"], "Fix quantities")
        self.assertEqual(demo.validate_action(action("set_thread_name", content="数量"))["content"], "数量")
        for name in ("", " " * 10, "x" * 101, "x\ny", "x\ry", "x\ty", "\x00", "x\x7fy", "x\u2028y", "\ud800"):
            with self.subTest(name=repr(name)):
                with self.assertRaises(demo.SafeError):
                    demo.validate_action(action("set_thread_name", content=name))
        with self.assertRaises(demo.SafeError):
            demo.validate_action(action("set_thread_name", "totals.py", "name"))

    def test_exact_action_schema_and_byte_limits(self):
        for bad in ({}, dict(action("test"), shell="whoami"), action("bash"),
                    action("write", "totals.py", "é" * 8001), action("finish", content="not allowed"),
                    dict(action("read", "totals.py"), message=123)):
            with self.subTest(bad=bad):
                with self.assertRaises(demo.SafeError):
                    demo.validate_action(bad)

    def test_provider_prose_errors_missing_structured_output_and_exit_failures_rejected(self):
        cli = demo.HostInference(Path("/nonrepo-empty"))
        cases = [
            (0, b"Everything is fixed!"),
            (0, b'{"type":"result","subtype":"success","is_error":true}'),
            (0, b'{"type":"result","subtype":"error","is_error":false}'),
            (0, b'{"type":"result","subtype":"success","is_error":false,"result":"prose"}'),
            (1, b"PRIVATE_PROVIDER_ERROR"),
        ]
        for result in cases:
            with self.subTest(result=result), patch.object(demo, "bounded_run", return_value=result):
                with self.assertRaises(demo.SafeError):
                    cli("goal")

    def test_host_inference_has_exact_disabled_tools_and_clean_environment(self):
        envelope = {"type": "result", "subtype": "success", "is_error": False,
                    "structured_output": action("read", "totals.py")}
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "synthetic-secret", "GITHUB_TOKEN": "synthetic-secret"}):
            with patch.object(demo, "bounded_run", return_value=(0, json.dumps(envelope).encode())) as run:
                cli = demo.HostInference(Path("/nonrepo-empty"))
                self.assertEqual(cli("goal"), envelope["structured_output"])
        args, kwargs = run.call_args
        argv, cwd, env = args
        self.assertEqual(set(env), {"HOME", "PATH", "LANG"})
        self.assertEqual(cwd, Path("/nonrepo-empty"))
        for option, value in (("--tools", ""), ("--mcp-config", '{"mcpServers":{}}'),
                              ("--setting-sources", ""), ("--settings", '{"disableAllHooks":true}'),
                              ("--output-format", "json")):
            self.assertEqual(argv[argv.index(option) + 1], value)
        self.assertIn("--strict-mcp-config", argv)
        self.assertIn("--no-session-persistence", argv)
        self.assertIn("--disable-slash-commands", argv)
        self.assertEqual(kwargs["stdin"], "goal")
        self.assertEqual(json.loads(argv[argv.index("--json-schema") + 1]), demo.ACTION_SCHEMA)

    def test_subprocess_timeout_and_output_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(demo.SafeError):
                demo.bounded_run([sys.executable, "-I", "-c", "import time; time.sleep(5)"],
                                 directory, demo.clean_env(directory), timeout=0.1)
            with self.assertRaises(demo.SafeError):
                demo.bounded_run([sys.executable, "-I", "-c", "print('x' * 10000)"],
                                 directory, demo.clean_env(directory), limit=100)

    def test_json_duplicate_keys_constants_and_invalid_unicode_rejected(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', b"\xff"):
            with self.assertRaises(demo.SafeError):
                demo.parse_json(raw)


if __name__ == "__main__":
    unittest.main()
