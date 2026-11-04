#!/usr/bin/env python3
"""Measures each scenario's hash.skipped and compares it with golden.json: a test target is
skipped when its hash at the checkout equals one a passing run stored.

usage: hashes.py <repo>, a `scenarios.sh build generated` history after one `tuist install`

`tuist hash selective-testing` passes no destination, so it leaves out UI test targets. A
target's hash is its own inputs plus its dependencies' hashes and the destination, so AppUITests'
stands in as App's hash plus its own sources.
"""
import json, os, re, subprocess, sys, tempfile

fixture = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(sys.argv[1])
golden = json.load(open(os.path.join(fixture, "golden.json")))
test_targets = list(golden["test_targets"])
suite_target = {test.split("/")[0]: t for t, v in golden["test_targets"].items() for test in v["tests"]}


def git(*args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=True).stdout.strip()


def measure():
    out = subprocess.run(["tuist", "hash", "selective-testing"], cwd=repo, capture_output=True, text=True, check=True).stdout
    hashes = dict(re.findall(r"^(\w+) - (\w+)$", out, re.M))
    with tempfile.NamedTemporaryFile() as index:
        env = {**os.environ, "GIT_INDEX_FILE": index.name}
        run = lambda *a: subprocess.run(["git", "-C", repo, *a], env=env, capture_output=True, text=True, check=True).stdout.strip()
        run("read-tree", "HEAD")
        run("add", "-A", "AppUITests")
        hashes["AppUITests"] = hashes["App"] + ":" + run("write-tree", "--prefix=AppUITests/")
    return hashes


cache = {}


def at_ref(ref):
    sha = git("rev-parse", f"refs/tags/{ref}^{{commit}}")
    if sha not in cache:
        git("reset", "-q", "--hard")
        git("clean", "-fdq")
        git("checkout", "-q", "--detach", sha)
        cache[sha] = measure()
    return cache[sha]


def at_checkout(name):
    subprocess.run([os.path.join(fixture, "scenarios.sh"), "checkout", repo, name], capture_output=True, check=True)
    return measure()


failures = 0
for s in golden["scenarios"]:
    expected = s["hash"]["skipped"]
    if expected is None:
        continue
    stored = {t: set() for t in test_targets}
    for r in s["runs"]:
        failing = {suite_target[f.split("/")[0]] for f in r.get("env", {}).get("TEST_RUNNER_TESTBED_FAILING_TESTS", "").split(",") if f}
        for t, h in at_ref(r["ref"]).items():
            if t in stored and t not in failing:
                stored[t].add(h)
    checkout = at_checkout(s["name"])
    measured = [t for t in test_targets if checkout[t] in stored[t]]
    if measured == expected:
        print(f"ok {s['name']}")
    else:
        failures += 1
        print(f"MISMATCH {s['name']}: measured {measured}, golden.json {expected}")

git("reset", "-q", "--hard")
git("clean", "-fdq")
sys.exit(1 if failures else 0)
