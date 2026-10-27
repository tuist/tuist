#!/usr/bin/env bash
# rust_libtest_junit.sh — run a Rust libtest binary and translate its
# structured JSON event stream into a JUnit `test.xml` at $XML_OUTPUT_FILE.
#
# Bazel sets $XML_OUTPUT_FILE for every test action and expects the runner
# to write a JUnit report there. rules_rs / rules_rust's rust_test uses
# stable libtest, which by default writes only human-readable text; without
# JUnit, Bazel synthesizes a one-case-per-target report and Tuist collapses
# the target to a single row. The wrapper unlocks libtest's structured
# per-test event stream (`--format=json --report-time`, both -Z
# unstable-options) via `RUSTC_BOOTSTRAP=1` on the pinned stable toolchain
# and writes one <testcase> per emitted event with libtest's own
# `exec_time`. Parsing pretty text with --test-threads=1 was the first
# attempt and lost cases whenever a test wrote to the process's real fds
# between the "test <name> ..." prefix and the trailing verdict (spotted by
# esnunes on the PR: kura's `startup::tests::startup_signals_are_handled_
# before_the_store_exists` disappeared under that shape).
#
# Invocation (from rust_junit_test in kura/bazel/rust_junit_test.bzl):
#   rust_libtest_junit.sh <test-binary> <public-target-name> [args...]
#
# The public target name is threaded through as the JUnit suite/classname so
# the durable per-case identity (name + classname + module) does not depend
# on the macro's private `.binary` inner-target suffix (also esnunes' note).
#
# Environment inputs from Bazel:
#   XML_OUTPUT_FILE — where JUnit XML must be written (required by Bazel)
#   TEST_TMPDIR     — writable scratch dir (used for the captured raw log)
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "rust_libtest_junit.sh: expected <binary> <suite> as first two arguments" >&2
  exit 2
fi

binary=$1
suite=$2
shift 2

if [[ ! -x $binary && -n ${RUNFILES_DIR:-} && -x $RUNFILES_DIR/$binary ]]; then
  binary=$RUNFILES_DIR/$binary
fi

raw=${TEST_TMPDIR:-/tmp}/${suite}.raw.log

set +e
RUSTC_BOOTSTRAP=1 "$binary" -Z unstable-options --format json --report-time "$@" | tee "$raw"
status=${PIPESTATUS[0]}
set -e

python3 - "$suite" "$raw" "$XML_OUTPUT_FILE" <<'PY'
import json
import sys
from xml.sax.saxutils import escape

suite, raw_path, xml_path = sys.argv[1:]

cases = []  # (name, verdict, duration_seconds, failure_message)

with open(raw_path, "r", errors="replace") as fh:
    for raw_line in fh:
        line = raw_line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            # A non-JSON line inside JSON output is either foreign output
            # from a test that wrote to the real fds or a libtest banner
            # line. Both are safe to skip: the "started"/"ok"/"failed" events
            # for a real case are always their own line.
            continue
        if event.get("type") != "test":
            continue
        verdict = event.get("event")
        if verdict not in ("ok", "failed", "ignored"):
            # "started" and any future variants are not terminal; ignore.
            continue
        name = event.get("name", "")
        duration = float(event.get("exec_time", 0.0) or 0.0)
        failure = event.get("stdout") if verdict == "failed" else None
        cases.append((name, verdict, duration, failure))

def testcase(name, verdict, duration, failure):
    body = ""
    if verdict == "failed":
        msg = (failure or "").strip() or "test failed"
        body = f'<failure message="test failed">{escape(msg)}</failure>'
    elif verdict == "ignored":
        body = '<skipped/>'
    return f'    <testcase name="{escape(name)}" classname="{escape(suite)}" time="{duration:.6f}">{body}</testcase>'

total = len(cases)
failed = sum(1 for _, v, _, _ in cases if v == "failed")
skipped = sum(1 for _, v, _, _ in cases if v == "ignored")

with open(xml_path, "w") as out:
    out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
    out.write('<testsuites>\n')
    out.write(
        f'  <testsuite name="{escape(suite)}" tests="{total}" failures="{failed}" skipped="{skipped}">\n'
    )
    for name, verdict, duration, failure in cases:
        out.write(testcase(name, verdict, duration, failure) + "\n")
    out.write('  </testsuite>\n')
    out.write('</testsuites>\n')
PY

exit "$status"
