#!/usr/bin/env python3
"""Local simulator Threads pilot, NOT a production or multi-tenant backend.

Run with /usr/bin/python3 thread_demo.py --data-dir /absolute/private/path.
Requires an existing host Claude Code login (claude auth login). This standalone
development harness is not connected to the native app's authenticated Threads API.
Only loopback HTTP is exposed; there is no authentication, cloud, cloning, PR
creation, notification, or Linux execution. Do not put secrets in user messages.
Repository choices in the real product come from the selected account's GitHub
App installation; this harness deliberately exposes only demo/checkout instead.
Each thread is a worktree of a disposable, fixed local Git fixture, never a user
checkout. Thread UUIDs, not model-supplied titles, determine branch identity.
SQLite owns the history and admission journal, independently of the phone.
An interrupted tool is outcome_unknown and requires human inspection, never replay.

Host Claude uses existing host authentication but has no tools, hooks, MCP, or
repository working directory. Its credentials are never copied into a workspace.
Only a separate sandboxed Python process executes generated fixture code. The
deprecated macOS sandbox-exec profile and canary are a narrow local demonstration,
not a general hostile-code sandbox or proof against adversarial test spoofing,
resource exhaustion, same-user filesystem tampering, or macOS vulnerabilities.
Only totals.py is writable; tests, argv, environment, and runtime are server-owned.
Test stdout/stderr and provider diagnostics are deliberately not journaled.
Use one server process and a disposable, private data directory outside the repo.
Retained threads contain user/model text and fixture source; delete the directory
manually after stopping the server when no longer needed.
"""

import argparse
import difflib
import fcntl
import json
import os
from pathlib import Path
import selectors
import signal
import sqlite3
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


MAX_TEXT = 4000
MAX_SOURCE = 16000
MAX_ACTIONS = 12
GOAL = "Fix calculate_total to account for quantities, and pass the fixed tests."
FIXTURE = {
    "totals.py": "def calculate_total(items):\n    return sum(price for price, quantity in items)\n",
    "test_totals.py": '''import runpy
import unittest

calculate_total = runpy.run_path("totals.py")["calculate_total"]


class TotalTests(unittest.TestCase):
    def test_quantities(self):
        self.assertEqual(calculate_total([(10, 2), (7, 3)]), 41)

    def test_different_quantities(self):
        self.assertEqual(calculate_total([(4, 3), (9, 2)]), 30)

    def test_empty(self):
        self.assertEqual(calculate_total([]), 0)


if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(TotalTests))
    if not result.wasSuccessful() or result.testsRun != 3:
        raise SystemExit(1)
    print("DEMO_TESTS_PASSED:3")
''',
}
ACTION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["kind", "path", "content", "message"],
    "properties": {
        "kind": {"type": "string", "enum": ["read", "write", "test", "finish", "set_thread_name"]},
        "path": {"type": "string", "enum": ["", "totals.py", "test_totals.py"]},
        "content": {"type": "string", "maxLength": MAX_SOURCE},
        "message": {"type": "string", "maxLength": MAX_TEXT},
    },
}


class SafeError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def clean_env(home):
    return {"HOME": str(home), "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"}


def bounded_run(argv, cwd, env, timeout=20, limit=65536, stdin=None):
    """No shell; bound both execution time and captured stdout, discard stderr."""
    with tempfile.TemporaryFile() as input_file:
        if stdin is not None:
            input_file.write(stdin.encode("utf-8"))
        input_file.seek(0)
        with subprocess.Popen(argv, cwd=cwd, env=env, stdin=input_file,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              start_new_session=True) as process:
            output = bytearray()
            deadline = time.monotonic() + timeout
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    while selector.get_map():
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            raise SafeError("Process timed out", 503)
                        for key, _ in selector.select(min(remaining, 0.1)):
                            chunk = os.read(key.fileobj.fileno(), 8192)
                            if not chunk:
                                selector.unregister(key.fileobj)
                            output.extend(chunk)
                            if len(output) > limit:
                                raise SafeError("Process output limit exceeded", 503)
                    code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
                return code, bytes(output)
            except subprocess.TimeoutExpired:
                raise SafeError("Process timed out", 503) from None
            finally:
                # Also reap descendants retaining pipes after the direct child exits.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()


def parse_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=unique,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError, RecursionError):
        raise SafeError("Invalid JSON") from None


def text_field(value, limit=MAX_TEXT):
    if not isinstance(value, str):
        raise SafeError("Expected text")
    try:
        valid = len(value.encode("utf-8")) <= limit and "\x00" not in value
    except UnicodeError:
        valid = False
    if not valid:
        raise SafeError("Text exceeds limits or is invalid")
    return value


def identifier(value):
    try:
        if not isinstance(value, str) or str(uuid.UUID(value)) != value:
            raise ValueError()
    except (ValueError, AttributeError):
        raise SafeError("Expected canonical UUID") from None
    return value


def exact_fields(value, fields):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise SafeError("Unexpected JSON fields")


def validate_action(action):
    exact_fields(action, ("kind", "path", "content", "message"))
    for field, limit in (("kind", 32), ("path", 64), ("content", MAX_SOURCE), ("message", MAX_TEXT)):
        text_field(action[field], limit)
    kind, path = action["kind"], action["path"]
    if kind not in ("read", "write", "test", "finish", "set_thread_name"):
        raise SafeError("Invalid action kind")
    if kind in ("read", "write"):
        if path not in FIXTURE or (kind == "write" and path != "totals.py"):
            raise SafeError("Path not permitted")
    elif path:
        raise SafeError("Action must not have a path")
    if kind == "set_thread_name":
        name = action["content"]
        if any(unicodedata.category(character).startswith("C") or character in "\u2028\u2029"
               for character in name):
            raise SafeError("Thread name must not contain control characters or newlines")
        name = name.strip()
        if not 1 <= len(name) <= 100:
            raise SafeError("Thread name must contain 1 to 100 characters")
        action = dict(action, content=name)
    elif kind != "write" and action["content"]:
        raise SafeError("Only writes or names may include content")
    return action


class HostInference:
    def __init__(self, directory):
        self.directory = directory
        self.cli = Path.home() / ".local/bin/claude"

    def check_help(self):
        code, raw = bounded_run([str(self.cli), "--help"], self.directory,
                                clean_env(Path.home()), timeout=15)
        required = ["--print", "--tools", "--disable-slash-commands", "--strict-mcp-config",
                    "--mcp-config", "--setting-sources", "--settings",
                    "--no-session-persistence", "--output-format", "--json-schema"]
        if code or any(option.encode() not in raw for option in required):
            raise SafeError("Installed Claude CLI lacks required options", 503)

    def __call__(self, prompt):
        argv = [str(self.cli), "--print", "--tools", "", "--disable-slash-commands",
                "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
                "--setting-sources", "", "--settings", '{"disableAllHooks":true}',
                "--no-session-persistence", "--output-format", "json",
                "--json-schema", json.dumps(ACTION_SCHEMA)]
        code, raw = bounded_run(argv, self.directory, clean_env(Path.home()),
                                timeout=180, limit=131072, stdin=prompt)
        if code:
            raise SafeError("Inference failed", 503)
        envelope = parse_json(raw)
        if (not isinstance(envelope, dict) or envelope.get("type") != "result"
                or envelope.get("subtype") != "success" or envelope.get("is_error") is not False
                or "structured_output" not in envelope):
            raise SafeError("Inference did not return structured success", 503)
        return validate_action(envelope["structured_output"])


class Sandbox:
    def __init__(self, private_dir):
        if sys.platform != "darwin" or not Path("/usr/bin/sandbox-exec").is_file():
            raise SafeError("macOS sandbox-exec is required", 503)
        # Resolve Apple's launcher once; do not allow xcrun or xcodebuild in the sandbox.
        code, raw = bounded_run(
            ["/usr/bin/python3", "-I", "-c",
             "import json,sys; print(json.dumps([sys.executable, sys.prefix]))"],
            private_dir, clean_env(private_dir))
        if code:
            raise SafeError("Apple Python runtime unavailable", 503)
        executable, prefix = parse_json(raw)
        self.python = str(Path(executable).resolve())
        self.prefix = str(Path(prefix).resolve())
        if not self.prefix.startswith(("/Applications/Xcode", "/Library/Developer/CommandLineTools/")):
            raise SafeError("Unsupported Apple Python runtime", 503)
        self.verify(private_dir)

    def profile(self, workspace):
        def literal(path):
            return "(literal " + json.dumps(str(path)) + ")"
        def subpath(path):
            return "(subpath " + json.dumps(str(path)) + ")"
        return "\n".join([
            "(version 1)", "(deny default)",
            "(allow process-exec " + literal(self.python) + " " +
            literal(Path(self.prefix) / "Resources/Python.app/Contents/MacOS/Python") + ")",
            "(allow file-read-metadata)", "(allow sysctl-read)",
            "(allow file-read* " + " ".join([
                literal("/"), literal("/dev/null"), literal("/dev/urandom"),
                literal("/dev/random"), subpath("/System/Library"),
                subpath("/usr/lib"), literal(self.python), subpath(self.prefix),
                subpath(workspace)]) + ")",
        ])

    def run(self, workspace, args):
        return bounded_run(["/usr/bin/sandbox-exec", "-p", self.profile(workspace),
                            self.python, "-I"] + args, workspace,
                           clean_env(workspace), timeout=10, limit=16384)

    def verify(self, private_dir):
        with tempfile.TemporaryDirectory(dir=private_dir) as root:
            root = Path(root).resolve()
            workspace = root / "workspace"
            workspace.mkdir(mode=0o700)
            canary = root / "outside-canary"
            canary.write_text("not-a-secret", encoding="utf-8")
            code = '''import socket
from pathlib import Path
import unittest
assert Path("inside").read_text() == "allowed"
try:
    Path(CANARY).read_bytes()
except PermissionError:
    pass
else:
    raise SystemExit(2)
try:
    socket.socket().connect(("127.0.0.1", 9))
except PermissionError:
    pass
else:
    raise SystemExit(3)
print("SANDBOX_VERIFIED")
'''.replace("CANARY", repr(str(canary)))
            (workspace / "inside").write_text("allowed", encoding="utf-8")
            result, output = self.run(workspace, ["-c", code])
            if result != 0 or output != b"SANDBOX_VERIFIED\n":
                raise SafeError("Sandbox canary verification failed; execution disabled", 503)

    def test(self, workspace):
        code, output = self.run(workspace, ["test_totals.py"])
        return code == 0 and output == b"DEMO_TESTS_PASSED:3\n"


class Backend:
    def __init__(self, data_dir, inference=None, start_worker=True):
        data_dir = Path(data_dir).expanduser()
        if not data_dir.is_absolute() or data_dir.is_symlink():
            raise SafeError("Data directory must be an absolute, non-symlink path")
        self.root = data_dir.resolve()
        repo = Path(__file__).resolve().parents[2]
        if self.root == repo or repo in self.root.parents:
            raise SafeError("Data directory must be outside the repository")
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        if self.root.stat().st_uid != os.getuid():
            raise SafeError("Data directory must be owned by this user")
        self.root.chmod(0o700)
        self.lock_file = open(self.root / "server.lock", "a+b")
        os.chmod(self.root / "server.lock", 0o600)
        try:
            fcntl.flock(self.lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.lock_file.close()
            raise SafeError("Data directory is already in use", 409) from None
        self.lock = threading.RLock()
        self.wake = threading.Event()
        self.stopping = threading.Event()
        self.worker = None
        try:
            self.workspaces = self.root / "workspaces"
            self.workspaces.mkdir(mode=0o700, exist_ok=True)
            self.fixture_repo = self.root / "fixture-repository"
            self._initialize_fixture()
            self.inference_dir = self.root / "inference-empty"
            self.inference_dir.mkdir(mode=0o700, exist_ok=True)
            if any(self.inference_dir.iterdir()):
                raise SafeError("Inference working directory must be empty")
            self.sandbox = Sandbox(self.root)
            self.inference = inference if inference is not None else HostInference(self.inference_dir)
            if inference is None:
                self.inference.check_help()
            self.db = sqlite3.connect(self.root / "threads.sqlite3", check_same_thread=False)
            os.chmod(self.root / "threads.sqlite3", 0o600)
            self.db.row_factory = sqlite3.Row
            self.db.executescript('''
                PRAGMA synchronous=FULL;
                CREATE TABLE IF NOT EXISTS threads (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, goal TEXT NOT NULL,
                    status TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
                    tested_revision INTEGER NOT NULL DEFAULT -1, steps INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS messages (
                    seq INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL,
                    thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS requests (
                    id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS actions (
                    id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL,
                    kind TEXT NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL,
                    result TEXT
                );
            ''')
            with self.db:
                self.db.execute("UPDATE threads SET status='outcome_unknown' WHERE id IN "
                                "(SELECT thread_id FROM actions WHERE state='executing')")
                self.db.execute("UPDATE actions SET state='outcome_unknown', result=? "
                                "WHERE state='executing'", ("Interrupted tool; no automatic retry",))
                self.db.execute("UPDATE threads SET status='queued' WHERE status='running'")
            if start_worker:
                self.worker = threading.Thread(target=self._worker, name="thread-demo-worker", daemon=True)
                self.worker.start()
        except BaseException:
            if hasattr(self, "db"):
                self.db.close()
            self.lock_file.close()
            raise

    def close(self):
        self.stopping.set()
        self.wake.set()
        if self.worker:
            self.worker.join()
        self.db.close()
        self.lock_file.close()

    def _git(self, args):
        env = clean_env(self.root)
        env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
                   GIT_TERMINAL_PROMPT="0")
        code, output = bounded_run(
            ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
             "-c", "user.name=Local Threads Demo", "-c", "user.email=thread-demo@localhost"] + args,
            self.fixture_repo, env)
        if code:
            raise SafeError("Disposable Git fixture operation failed", 503)
        return output.decode("utf-8")

    def _initialize_fixture(self):
        if self.fixture_repo.exists():
            if self.fixture_repo.is_symlink() or not (self.fixture_repo / ".git").is_dir():
                raise SafeError("Invalid disposable fixture repository")
            for name, source in FIXTURE.items():
                if self._git(["show", "main:" + name]) != source:
                    raise SafeError("Fixed fixture commit was modified")
            return
        self.fixture_repo.mkdir(mode=0o700)
        self._git(["init", "--initial-branch=main", "--template="])
        for name, source in FIXTURE.items():
            (self.fixture_repo / name).write_text(source, encoding="utf-8")
            (self.fixture_repo / name).chmod(0o600)
        self._git(["add", "--", "totals.py", "test_totals.py"])
        self._git(["commit", "-m", "Fixed disposable quantity fixture"])

    def _message(self, thread_id, role, content):
        self.db.execute("INSERT INTO messages(id,thread_id,role,content) VALUES(?,?,?,?)",
                        (str(uuid.uuid4()), thread_id, role, content))

    def _row(self, thread_id):
        row = self.db.execute("SELECT * FROM threads WHERE id=?", (thread_id,)).fetchone()
        if row is None:
            raise SafeError("Thread not found", 404)
        return row

    def _file(self, thread_id, name, write=None):
        if name not in FIXTURE or (write is not None and name != "totals.py"):
            raise SafeError("Path not permitted")
        if write is not None:
            text_field(write, MAX_SOURCE)
        workspace = self.workspaces / identifier(thread_id)
        if workspace.is_symlink() or workspace.resolve().parent != self.workspaces.resolve():
            raise SafeError("Unsafe workspace")
        directory = os.open(workspace, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            flags = os.O_NOFOLLOW | os.O_NONBLOCK | (os.O_WRONLY if write is not None else os.O_RDONLY)
            fd = os.open(name, flags, dir_fd=directory)
            with os.fdopen(fd, "wb" if write is not None else "rb") as file:
                info = os.fstat(file.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > MAX_SOURCE:
                    raise SafeError("Unsafe workspace file")
                if write is not None:
                    file.truncate(0)
                    file.write(write.encode("utf-8"))
                    file.flush()
                    os.fsync(file.fileno())
                    return write
                return text_field(file.read(MAX_SOURCE + 1).decode("utf-8"), MAX_SOURCE)
        finally:
            os.close(directory)

    def _diff(self, thread_id):
        try:
            current = self._file(thread_id, "totals.py")
        except FileNotFoundError:
            if self._row(thread_id)["status"] == "outcome_unknown":
                return ""
            raise
        return "".join(difflib.unified_diff(
            FIXTURE["totals.py"].splitlines(keepends=True),
            current.splitlines(keepends=True),
            fromfile="a/totals.py", tofile="b/totals.py"))

    def get(self, thread_id):
        identifier(thread_id)
        with self.lock:
            row = self._row(thread_id)
            messages = self.db.execute("SELECT id,role,content FROM messages WHERE thread_id=? ORDER BY seq",
                                       (thread_id,)).fetchall()
            return {"id": row["id"], "title": row["title"], "goal": row["goal"],
                    "branch": "code/" + thread_id, "repository": "demo/checkout",
                    "profile": "macos", "status": row["status"], "visibility": "private",
                    "messages": [dict(message) for message in messages], "diff": self._diff(thread_id)}

    def list_threads(self):
        with self.lock:
            ids = self.db.execute("SELECT id FROM threads ORDER BY rowid DESC").fetchall()
            return {"threads": [self.get(row["id"]) for row in ids]}

    def _request(self, request_id, payload, thread_id=None):
        row = self.db.execute("SELECT * FROM requests WHERE id=?", (request_id,)).fetchone()
        if row is not None:
            if row["payload"] != payload or (thread_id and row["thread_id"] != thread_id):
                raise SafeError("Request id already used with different input", 409)
            return row["thread_id"]
        return None

    def create(self, body):
        exact_fields(body, ("goal", "profile", "request_id"))
        goal = text_field(body["goal"])
        if not goal.strip() or body["profile"] != "macos":
            raise SafeError("Nonempty goal and macos profile required")
        request_id = identifier(body["request_id"])
        payload = json.dumps(["create", goal, "macos"])
        with self.lock:
            existing = self._request(request_id, payload)
            if existing:
                return self.get(existing)
            thread_id = str(uuid.uuid4())
            workspace = self.workspaces / thread_id
            with self.db:
                self.db.execute("INSERT INTO threads(id,title,goal,status) VALUES(?,?,?,'running')",
                                (thread_id, "New thread", goal))
                self._message(thread_id, "user", goal)
                self.db.execute("INSERT INTO requests VALUES(?,?,?)", (request_id, thread_id, payload))
                cursor = self.db.execute("INSERT INTO actions(thread_id,kind,state,payload) "
                                         "VALUES(?,'create_worktree','executing',?)",
                                         (thread_id, json.dumps({"branch": "code/" + thread_id})))
                admission = cursor.lastrowid
            try:
                self._git(["worktree", "add", "-b", "code/" + thread_id, str(workspace), "main"])
                workspace.chmod(0o700)
                for name in FIXTURE:
                    (workspace / name).chmod(0o600)
                with self.db:
                    self.db.execute("UPDATE actions SET state='completed',result='Fixed worktree created' WHERE id=?",
                                    (admission,))
                    self.db.execute("UPDATE threads SET status='queued' WHERE id=?", (thread_id,))
                    self._message(thread_id, "tool", "Fixed demo/checkout worktree created")
            except Exception:
                with self.db:
                    self.db.execute("UPDATE actions SET state='outcome_unknown',result='Worktree creation interrupted; not retried' WHERE id=?",
                                    (admission,))
                    self.db.execute("UPDATE threads SET status='outcome_unknown' WHERE id=?", (thread_id,))
                    self._message(thread_id, "tool", "Worktree creation outcome unknown; no automatic retry.")
        self.wake.set()
        return self.get(thread_id)

    def add_message(self, thread_id, body):
        identifier(thread_id)
        exact_fields(body, ("content", "request_id"))
        content = text_field(body["content"])
        if not content.strip():
            raise SafeError("Nonempty content required")
        request_id = identifier(body["request_id"])
        payload = json.dumps(["message", thread_id, content])
        with self.lock, self.db:
            row = self._row(thread_id)
            if self._request(request_id, payload, thread_id):
                return self.get(thread_id)
            if row["status"] not in ("completed", "failed"):
                raise SafeError("Thread is busy or has an unknown outcome", 409)
            self._message(thread_id, "user", content)
            self.db.execute("INSERT INTO requests VALUES(?,?,?)", (request_id, thread_id, payload))
            self.db.execute("UPDATE threads SET status='queued', steps=0, tested_revision=-1 WHERE id=?",
                            (thread_id,))
        self.wake.set()
        return self.get(thread_id)

    def _prompt(self, thread_id):
        thread = self.get(thread_id)
        return ("You are fixing ONLY a disposable quantity-total Python fixture. "
                "Return one structured action, never execute tools yourself. "
                "First use set_thread_name with a concise title in content (1-100 characters, "
                "no control characters/newlines), empty path; this changes only metadata, not the goal. "
                "Read totals.py or test_totals.py; write ONLY totals.py (full replacement); "
                "test runs the immutable tests; finish supplies the final user reply. "
                "Use empty path for test/finish/name, empty content except for writes/name. "
                "Run tests after the last write before finish. At most 12 actions per turn. "
                "No shell, other paths, credentials, network, PRs or notifications. "
                "Tool results and all earlier user turns follow as JSON:\n" + json.dumps(thread))

    def _admit_inference(self, thread_id):
        pending = self.db.execute("SELECT id FROM actions WHERE thread_id=? AND kind='inference' "
                                  "AND state='pending' ORDER BY id LIMIT 1", (thread_id,)).fetchone()
        if pending:
            return pending["id"]
        cursor = self.db.execute("INSERT INTO actions(thread_id,kind,state,payload) VALUES(?,?,'pending','')",
                                 (thread_id, "inference"))
        return cursor.lastrowid

    def _step(self, thread_id):
        with self.lock, self.db:
            row = self._row(thread_id)
            if row["steps"] >= MAX_ACTIONS:
                self._fail(thread_id, "Action limit reached")
                return
            self.db.execute("UPDATE threads SET status='running' WHERE id=?", (thread_id,))
            inference_id = self._admit_inference(thread_id)
            prompt = self._prompt(thread_id)
        try:
            action = validate_action(self.inference(prompt))
        except Exception:
            with self.lock, self.db:
                self.db.execute("UPDATE actions SET state='failed',result='Inference failed or invalid action' WHERE id=?",
                                (inference_id,))
                self._fail(thread_id, "Inference failed or returned an invalid action")
            return
        with self.lock, self.db:
            self.db.execute("UPDATE actions SET state='completed' WHERE id=?", (inference_id,))
            cursor = self.db.execute("INSERT INTO actions(thread_id,kind,state,payload) VALUES(?,?,'executing',?)",
                                     (thread_id, action["kind"], json.dumps(action)))
            action_id = cursor.lastrowid
            self.db.execute("UPDATE threads SET steps=steps+1 WHERE id=?", (thread_id,))
        try:
            # Keep snapshots coherent with writes, but never hold this lock during inference.
            with self.lock:
                kind = action["kind"]
                passed = False
                if kind == "read":
                    evidence = action["path"] + ":\n" + self._file(thread_id, action["path"])
                elif kind == "write":
                    self._file(thread_id, action["path"], action["content"])
                    evidence = "Wrote totals.py"
                elif kind == "test":
                    if self._file(thread_id, "test_totals.py") != FIXTURE["test_totals.py"]:
                        raise SafeError("Fixed tests were modified")
                    self._file(thread_id, "totals.py")
                    passed = self.sandbox.test(self.workspaces / thread_id)
                    evidence = "Fixed tests: 3 passed" if passed else "Fixed tests failed"
                elif kind == "set_thread_name":
                    evidence = "Thread named: " + action["content"]
                else:
                    row = self._row(thread_id)
                    passed = row["tested_revision"] == row["revision"]
                    evidence = "Finish accepted" if passed else "Finish rejected: passing tests required after last write"
                with self.db:
                    if kind == "set_thread_name":
                        self.db.execute("UPDATE threads SET title=? WHERE id=?", (action["content"], thread_id))
                    elif kind == "write":
                        self.db.execute("UPDATE threads SET revision=revision+1,tested_revision=-1 WHERE id=?", (thread_id,))
                    elif kind == "test":
                        self.db.execute("UPDATE threads SET tested_revision=" + ("revision" if passed else "-1") + " WHERE id=?",
                                        (thread_id,))
                    elif kind == "finish":
                        self.db.execute("UPDATE threads SET status=? WHERE id=?",
                                        ("completed" if passed else "failed", thread_id))
                    self._message(thread_id, "tool", evidence)
                    if kind == "finish":
                        self._message(thread_id, "assistant", action["message"] if passed else evidence)
                    self.db.execute("UPDATE actions SET state='completed',result=? WHERE id=?", (evidence, action_id))
        except Exception:
            with self.lock, self.db:
                self.db.execute("UPDATE actions SET state='outcome_unknown',result='Tool interrupted or failed; not retried' WHERE id=?",
                                (action_id,))
                self.db.execute("UPDATE threads SET status='outcome_unknown' WHERE id=?", (thread_id,))
                self._message(thread_id, "tool", "Tool outcome unknown; inspect locally. No automatic retry.")

    def _fail(self, thread_id, message):
        self.db.execute("UPDATE threads SET status='failed' WHERE id=?", (thread_id,))
        self._message(thread_id, "assistant", message)

    def _worker(self):
        while not self.stopping.is_set():
            with self.lock:
                row = self.db.execute("SELECT id FROM threads WHERE status IN ('queued','running') ORDER BY rowid LIMIT 1").fetchone()
            if row is None:
                self.wake.wait(0.5)
                self.wake.clear()
                continue
            try:
                self._step(row["id"])
            except Exception:
                with self.lock, self.db:
                    executing = self.db.execute("SELECT 1 FROM actions WHERE thread_id=? AND state='executing'", (row["id"],)).fetchone()
                    if executing:
                        self.db.execute("UPDATE threads SET status='outcome_unknown' WHERE id=?", (row["id"],))
                    else:
                        self._fail(row["id"], "Local worker failed safely")


class LocalServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, backend, port=8791):
        self.backend = backend
        super().__init__(("127.0.0.1", port), Handler)


class Handler(BaseHTTPRequestHandler):
    server_version = "LocalThreadsPilot"

    def log_message(self, *_):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def _body(self):
        if self.headers.get("Transfer-Encoding") or self.headers.get_content_type() != "application/json":
            raise SafeError("Expected fixed-length application/json")
        lengths = self.headers.get_all("Content-Length", [])
        if len(lengths) != 1 or not lengths[0].isascii() or not lengths[0].isdigit():
            raise SafeError("Invalid Content-Length")
        length = int(lengths[0])
        if length <= 0 or length > 32768:
            raise SafeError("Request body too large", 413)
        raw = self.rfile.read(length)
        if len(raw) != length:
            raise SafeError("Incomplete body")
        return parse_json(raw)

    def _dispatch(self, post=False):
        try:
            if self.headers.get("Origin") is not None:
                raise SafeError("Browser origins are not allowed", 403)
            if self.headers.get("Host") not in ("127.0.0.1:" + str(self.server.server_port),
                                                "localhost:" + str(self.server.server_port)):
                raise SafeError("Invalid loopback Host", 403)
            parts = self.path.split("/")
            backend = self.server.backend
            if self.path == "/threads":
                result = backend.create(self._body()) if post else backend.list_threads()
            elif len(parts) == 3 and parts[1] == "threads" and not post:
                result = backend.get(parts[2])
            elif len(parts) == 4 and parts[1] == "threads" and parts[3] == "messages" and post:
                result = backend.add_message(parts[2], self._body())
            else:
                raise SafeError("Route not found", 404)
            self._reply(200, result)
        except SafeError as error:
            self._reply(error.status, {"error": str(error)})
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            self._reply(500, {"error": "Local request failed"})

    def _reply(self, status, result):
        raw = json.dumps(result, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(raw)

    def do_GET(self):
        self._dispatch()

    def do_POST(self):
        self._dispatch(post=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8791)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    os.umask(0o077)
    backend = None
    server = None
    try:
        backend = Backend(args.data_dir)
        server = LocalServer(backend, args.port)
        print("Local Threads pilot: http://127.0.0.1:" + str(args.port), flush=True)
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    except Exception:
        print("Local Threads pilot could not start; check private data directory, Apple Python, sandbox and Claude CLI.", file=sys.stderr)
        return 1
    finally:
        if server:
            server.server_close()
        if backend:
            backend.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
