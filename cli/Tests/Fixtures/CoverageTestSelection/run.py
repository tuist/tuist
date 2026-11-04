#!/usr/bin/env python3
"""Runs one scenario of the test bed end to end against a Tuist server and compares what
coverage-based test selection decided with golden.json. See "End to end" in README.md.

usage: scenarios.sh run <repo> <scenario> [--sharded]

<repo> is a `scenarios.sh build generated` history. The script records the scenario's runs with
`tuist test`, checks the scenario out, runs `tuist test` with selection (with --sharded, a
build-only shard plan and two `--without-building` shards), and exits 1 when the hash skips, the
outcome, the reason or the tests that ran and were skipped differ from golden.json.

A local reverse proxy sits between the CLI and the server and records the selection requests and
their answers, so the decisions are read without access to the server's databases.
"""
import argparse, http.client, http.server, json, os, re, subprocess, sys, threading, time, urllib.parse, urllib.request, zlib

fixture = os.path.dirname(os.path.abspath(__file__))
golden = json.load(open(os.path.join(fixture, "golden.json")))
suite_module = {test.split("/")[0]: module for module, v in golden["test_targets"].items() for test in v["tests"]}


def norm(test):
    return test[:-2] if test.endswith("()") else test


def parse_args():
    env = os.environ.get
    p = argparse.ArgumentParser(prog="scenarios.sh run", description=__doc__.split("\n\n")[0])
    p.add_argument("repo")
    p.add_argument("scenario")
    p.add_argument("--sharded", action="store_true", help="plan two shards with --build-only, then run each with --without-building")
    p.add_argument("--project", default=env("TUIST_TESTBED_PROJECT"),
                   help="full handle of a project nothing has run against yet (TUIST_TESTBED_PROJECT)")
    p.add_argument("--url", default=env("TUIST_TESTBED_URL", "http://127.0.0.1:8080"),
                   help="the server (TUIST_TESTBED_URL, default http://127.0.0.1:8080)")
    p.add_argument("--tuist", default=env("TUIST_TESTBED_CLI", "tuist"), help="the CLI binary (TUIST_TESTBED_CLI, default tuist)")
    p.add_argument("--destination", default=env("TUIST_TESTBED_DESTINATION", "platform=iOS Simulator,name=iPhone 17"),
                   help="xcodebuild -destination (TUIST_TESTBED_DESTINATION)")
    p.add_argument("--work", default=env("TUIST_TESTBED_WORK"),
                   help="logs, derived data and the CLI cache (TUIST_TESTBED_WORK, default <repo>.runs/<project>)")
    p.add_argument("--ingest-wait", type=int, default=int(env("TUIST_TESTBED_INGEST_WAIT", "45")),
                   help="seconds to wait before the checkout so the server finishes ingesting the last run (default 45)")
    p.add_argument("--clickhouse", default=env("TUIST_TESTBED_CLICKHOUSE"),
                   help="optional ClickHouse HTTP URL with ?database=, such as a dev server's "
                        "http://127.0.0.1:8123/?database=tuist_development (TUIST_TESTBED_CLICKHOUSE)")
    a = p.parse_args()
    if not a.project or "/" not in a.project:
        p.error("pass --project <account>/<project> or set TUIST_TESTBED_PROJECT")
    if not os.environ.get("TUIST_TOKEN"):
        p.error("set TUIST_TOKEN to a token of the project: the proxy's URL has no CLI session")
    return a


# The proxy

class Recorder:
    def __init__(self, path):
        self.path, self.lock, self.calls = path, threading.Lock(), []

    def add(self, record):
        with self.lock:
            self.calls.append(record)
            with open(self.path, "a") as f:
                f.write(json.dumps(record) + "\n")


def decode(body, encoding):
    if body and (encoding or "").lower() == "gzip":
        try:
            return zlib.decompressobj(31).decompress(body)
        except zlib.error:
            return body
    return body


def start_proxy(upstream, recorder):
    target = urllib.parse.urlsplit(upstream)
    connection_class = http.client.HTTPSConnection if target.scheme == "https" else http.client.HTTPConnection

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def forward(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else None
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")}
            started = time.time()
            upstream_connection = connection_class(target.netloc, timeout=900)
            upstream_connection.request(self.command, self.path, body=body, headers=headers)
            response = upstream_connection.getresponse()
            data = response.read()
            elapsed_ms = int((time.time() - started) * 1000)
            self.send_response(response.status)
            for k, v in response.getheaders():
                if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            path = self.path.split("?")[0]
            if "/tests/selective-testing/coverage/" in path:
                record = {"path": path, "status": response.status, "ms": elapsed_ms}
                for key, raw, encoding in (("request", body, self.headers.get("Content-Encoding")),
                                           ("response", data, response.getheader("Content-Encoding"))):
                    try:
                        record[key] = json.loads(decode(raw, encoding) or b"null")
                    except ValueError:
                        record[key] = None
                recorder.add(record)

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = forward

    class Server(http.server.ThreadingHTTPServer):
        daemon_threads = True

    server = Server(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_address[1]}"


# The repository

def git(repo, *args, check=True):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=check).stdout.strip()


def configure(repo, project, url):
    """Writes the server, the project and the coverage strategy into Tuist.swift, hidden from git
    so that every run uploads as a clean checkout, and gives the repository its own remote URL."""
    if not os.path.exists(os.path.join(repo, "Project.swift")):
        sys.exit("run supports the generated variant only: build <repo> with `scenarios.sh build generated`")
    if not git(repo, "rev-parse", "-q", "--verify", "refs/tags/baseline", check=False):
        sys.exit(f"{repo} isn't a test bed history: run `scenarios.sh build generated {repo}`")
    git(repo, "reset", "-q", "--hard")
    git(repo, "clean", "-fdq")
    git(repo, "update-index", "--no-skip-worktree", "Tuist.swift")
    git(repo, "checkout", "-q", "--", "Tuist.swift")
    with open(os.path.join(repo, "Tuist.swift"), "w") as f:
        f.write(f"""import ProjectDescription

let tuist = Tuist(
    fullHandle: {json.dumps(project)},
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    url: {json.dumps(url)},
    project: .tuist()
)
""")
    git(repo, "update-index", "--skip-worktree", "Tuist.swift")
    # The server keys commit history by repository, so a reused URL carries one project's history into the next.
    remote = f"https://github.com/tuist-testbed/{project.replace('/', '-')}.git"
    if git(repo, "remote", check=False).split().count("origin"):
        git(repo, "remote", "set-url", "origin", remote)
    else:
        git(repo, "remote", "add", "origin", remote)


def check_out_ref(repo, ref, branch):
    git(repo, "reset", "-q", "--hard")
    git(repo, "clean", "-fdq")
    if branch:
        git(repo, "checkout", "-q", "-B", branch, f"refs/tags/{ref}")
    else:
        git(repo, "checkout", "-q", "--detach", f"refs/tags/{ref}")


# Running tuist

class Runner:
    def __init__(self, args, proxy_url, work):
        self.args, self.work = args, work
        self.env = {**os.environ, "TUIST_URL": proxy_url, "CI": "1",
                    "TUIST_XDG_CACHE_HOME": os.path.join(work, "cache")}
        self.logs = os.path.join(work, "logs")
        os.makedirs(self.logs, exist_ok=True)

    def tuist(self, label, arguments, extra_env=None):
        log = os.path.join(self.logs, f"{label}.log")
        command = [self.args.tuist, *arguments]
        with open(log, "a") as f:
            f.write(f"$ {' '.join(command)}\n")
            f.flush()
            started = time.time()
            code = subprocess.run(command, cwd=self.args.repo, env={**self.env, **(extra_env or {})},
                                  stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL).returncode
            f.write(f"== exit {code} in {int(time.time() - started)}s\n")
        return code, open(log, errors="replace").read()

    def test(self, label, scheme, extra_env=None, sharded=False):
        dd = os.path.join(self.work, "derived-data")
        tail = ["--inspect-mode", "local", "--", "-destination", self.args.destination]
        if not sharded:
            return self.tuist(label, ["test", scheme, "--derived-data-path", dd, *tail], extra_env)
        reference = f"{label}-{int(time.time())}"
        code, log = self.tuist(label, ["test", scheme, "--build-only", "--shard-total", "2", "--shard-granularity", "suite",
                                       "--shard-reference", reference, "--derived-data-path", dd, *tail], extra_env)
        if code != 0:
            return code, log
        # Shards on CI get their own checkout. Here, the plan's matrix file would make them upload as dirty.
        matrix = os.path.join(self.args.repo, ".tuist-shard-matrix.json")
        if os.path.exists(matrix):
            os.remove(matrix)
        for index in (0, 1):
            shard_code, log = self.tuist(label, ["test", "--without-building", "--shard-index", str(index),
                                                 "--shard-reference", reference, "--derived-data-path", f"{dd}-shard{index}",
                                                 *tail], extra_env)
            code = code or shard_code
        return code, log


# Comparing with golden.json

def clickhouse(url, query):
    request = urllib.request.Request(url + ("&" if "?" in url else "?") + "default_format=JSON", data=query.encode())
    body = urllib.request.urlopen(request, timeout=600).read()
    return json.loads(body).get("data", []) if body.strip() else []


def evaluate(scenario, log, calls, args):
    problems, result = [], {"scenario": scenario["name"], "sharded": args.sharded}
    test_targets = golden["test_targets"]

    match = re.search(r"will be skipped: (.*)", log)
    if match:
        hash_skipped = sorted(t.strip() for t in match.group(1).split(","))
    elif "test action has no tests to run" in log:
        hash_skipped = sorted(test_targets)
    else:
        hash_skipped = []
    result["hash_skipped"] = hash_skipped
    expected_hash = (scenario.get("hash") or {}).get("skipped")
    if expected_hash is not None and sorted(expected_hash) != hash_skipped:
        problems.append(f"hash skipped {hash_skipped}, golden {sorted(expected_hash)}")

    runs = [c for c in calls if c["path"].endswith("/coverage/runs")]
    run = runs[-1]["response"] if runs else None
    result["impact_run"] = run
    result["cli"] = re.findall(r"Coverage-based test selection[^\n]*", log)
    outcome = scenario["outcome"]
    if outcome == "no_selection_call":
        if runs:
            problems.append(f"expected no selection call, got {run.get('outcome')} {run.get('reason') or ''}".strip())
    elif not run:
        problems.append(f"the selection call answered {runs[-1]['status']}" if runs else "the CLI never asked the server to select")
    else:
        if run.get("outcome") != outcome:
            problems.append(f"outcome {run.get('outcome')}, golden {outcome}")
        if outcome == "fallback" and run.get("reason") != scenario.get("reason"):
            problems.append(f"reason {run.get('reason')}, golden {scenario.get('reason')}")
        if outcome == "fallback" and scenario.get("matched_path") and run.get("matched_path") != scenario["matched_path"]:
            problems.append(f"matched path {run.get('matched_path')}, golden {scenario['matched_path']}")

    ran = {}
    for status, suite, name in re.findall(r"([✔✖]) \[(\w+)\] (\S+) on ", log):
        key = f"{suite_module.get(suite, '?')}/{suite}/{norm(name)}"
        ran[key] = "passed" if status == "✔" and ran.get(key) != "failed" else "failed"
    result["ran"] = ran

    if outcome == "selected" and run and run.get("outcome") == "selected":
        expected_ran = {norm(k) for k, v in scenario["run"].items() if v.get("exists_at_checkout", True)}
        expected_skip = {norm(k) for k in scenario.get("skip") or {}}
        skipped = set()
        for t in run.get("skipped_tests") or []:
            if t.get("name"):
                skipped.add(f"{t['module']}/{t['suite']}/{norm(t['name'])}")
            else:  # The whole module.
                skipped |= {f"{t['module']}/{norm(test)}" for test in test_targets.get(t["module"], {}).get("tests", [])}
        result["skipped"] = sorted(skipped)
        for k in sorted(expected_skip - skipped):
            problems.append(f"not skipped {k}")
        for k in sorted(skipped - expected_skip):
            problems.append(f"skipped {k}, golden doesn't skip it")
    elif outcome == "fallback":
        expected_ran = {f"{m}/{norm(t)}" for m in scenario["run_targets"] for t in test_targets[m]["tests"]}
    else:
        expected_ran = {norm(k) for k in scenario.get("run") or {}}
    for k in sorted(expected_ran - set(ran)):
        problems.append(f"didn't run {k}")
    for k in sorted(set(ran) - expected_ran):
        problems.append(f"ran {k}, golden doesn't run it")

    if args.clickhouse and run and run.get("outcome") == "selected":
        rows = clickhouse(args.clickhouse, "select module_name, suite_name, name, reason, matched_path from test_impact_run_tests "
                                           f"where test_impact_run_id = '{run['id']}'")
        got = {f"{r['module_name']}/{r['suite_name']}/{norm(r['name'])}": (r["reason"], r["matched_path"] or "") for r in rows}
        expected = {norm(k): (v["reason"], v.get("matched_path", "")) for k, v in scenario["run"].items()
                    if v.get("known_to_server", True)}
        result["reasons"] = got
        for k in sorted(set(expected) | set(got)):
            if k not in got:
                problems.append(f"no decision recorded for {k}")
            elif k not in expected:
                problems.append(f"decision recorded for {k}, golden has none")
            elif got[k] != expected[k]:
                problems.append(f"{k} decided {got[k]}, golden {expected[k]}")

    result["problems"] = problems
    return result


def main():
    args = parse_args()
    args.repo = os.path.abspath(args.repo)
    scenario = next((s for s in golden["scenarios"] if s["name"] == args.scenario), None)
    if not scenario:
        sys.exit(f"Unknown scenario: {args.scenario}")
    work = os.path.abspath(args.work or f"{args.repo}.runs/{args.project.replace('/', '-')}{'-sharded' if args.sharded else ''}")
    if os.path.exists(os.path.join(work, "result.json")):
        sys.exit(f"{work} already holds a run: use a fresh project, or remove it")
    os.makedirs(work, exist_ok=True)

    configure(args.repo, args.project, args.url)
    recorder = Recorder(os.path.join(work, "requests.jsonl"))
    runner = Runner(args, start_proxy(args.url, recorder), work)
    print(f"Logs in {work}")

    if not os.path.isdir(os.path.join(args.repo, "Tuist", ".build")):
        code, _ = runner.tuist("install", ["install"])
        if code != 0:
            sys.exit(f"tuist install failed, see {runner.logs}/install.log")

    default_scheme = scenario.get("scheme", golden["scheme"])
    for index, run in enumerate(scenario["runs"]):
        check_out_ref(args.repo, run["ref"], run["branch"])
        label = f"run{index:02d}"
        code, _ = runner.test(label, run.get("scheme", golden["scheme"]), run.get("env"))
        print(f"{label} {run['ref']} on {run['branch'] or 'a detached HEAD'}: exit {code}")
        if code != 0 and "TEST_RUNNER_TESTBED_FAILING_TESTS" not in run.get("env", {}):
            sys.exit(f"{label} failed, see {runner.logs}/{label}.log")

    if scenario["runs"]:
        time.sleep(args.ingest_wait)
    if args.clickhouse:
        # Evidence rows merge in the background; testing against the merged state keeps runs repeatable.
        clickhouse(args.clickhouse, "OPTIMIZE TABLE coverage_test_sources FINAL")
    subprocess.run([os.path.join(fixture, "scenarios.sh"), "checkout", args.repo, args.scenario], check=True, capture_output=True)
    checkout_env = {}
    if scenario["checkout"].get("merge_parents"):
        # A detached merge commit is a pull request checkout: these are what GitHub Actions sets.
        checkout_env = {"GITHUB_REF": "refs/pull/1/merge", "GITHUB_BASE_REF": golden["default_branch"],
                        "GITHUB_HEAD_REF": f"feature/{args.scenario.replace('_', '-')}"}
    before = len(recorder.calls)
    code, log = runner.test("checkout", default_scheme, checkout_env, sharded=args.sharded)
    print(f"checkout {scenario['checkout']['ref']}{' sharded' if args.sharded else ''}: exit {code}")

    result = evaluate(scenario, log, recorder.calls[before:], args)
    result["exit_code"] = code
    if code != 0:
        result["problems"].insert(0, f"tuist test exited {code}")
    json.dump(result, open(os.path.join(work, "result.json"), "w"), indent=1)
    if result["problems"]:
        print(f"FAIL {args.scenario}:\n  " + "\n  ".join(result["problems"]))
        sys.exit(1)
    run = result["impact_run"] or {}
    print(f"PASS {args.scenario}: {run.get('outcome', 'no selection call')}"
          f"{' ' + run['reason'] if run.get('reason') else ''}, {len(result['ran'])} tests ran,"
          f" hash skipped {result['hash_skipped']}")


if __name__ == "__main__":
    main()
