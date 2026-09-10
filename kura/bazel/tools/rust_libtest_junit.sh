#!/usr/bin/env bash
# rust_libtest_junit.sh — run a Rust libtest binary and translate its stable
# text output into a JUnit `test.xml` at $XML_OUTPUT_FILE.
#
# Bazel sets $XML_OUTPUT_FILE for every test action and expects the runner to
# write a JUnit report there. rules_rs / rules_rust's rust_test uses stable
# libtest, which writes only human-readable text; without JUnit, Bazel
# synthesizes a one-case-per-target report and Tuist collapses the target to
# a single row. This wrapper parses the text output line by line and writes
# real per-case rows so Tuist Test Insights shows every #[test].
#
# Invocation (from rust_junit_test in kura/bazel/rust_junit_test.bzl):
#   rust_libtest_junit.sh <test-binary> [args-forwarded-to-binary...]
#
# Environment inputs from Bazel:
#   XML_OUTPUT_FILE — where JUnit XML must be written (required by Bazel)
#   TEST_TMPDIR     — writable scratch dir (used for the captured raw log)
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "rust_libtest_junit.sh: expected the test binary as first argument" >&2
  exit 2
fi

binary=$1
shift

# Bazel's runfiles: convert Bazel's short-path arg into a real path we can
# execute regardless of how the wrapper is invoked (bazel test vs. bazel run).
if [[ ! -x $binary && -n ${RUNFILES_DIR:-} && -x $RUNFILES_DIR/$binary ]]; then
  binary=$RUNFILES_DIR/$binary
fi

suite=$(basename "$binary")
raw=${TEST_TMPDIR:-/tmp}/${suite}.raw.log

# --format=pretty is the libtest default and is what emits one
# "test <name> ... <result>" line per case; --format=terse (which I first
# tried) only prints a dot per pass, which leaves the parser with nothing to
# match. --test-threads=1 forces serial execution so consecutive output
# lines correspond to consecutive test wall-clock windows: with parallel
# tests, lines interleave and per-case timing collapses. The runtime cost
# vs. the default parallelism is real (roughly 4x on kura's ~1000-case
# suite) but is worth it for populated per-case duration percentiles in
# Tuist Test Insights, since stable libtest does not expose --report-time.
#
# Each stdout line is prefixed with the wall-clock second at which the
# wrapper observed it. The Python parser derives per-case duration from the
# gap between a case's completion line and the previous one, and the "running
# N tests" line seeds the first case.
set +e
"$binary" --format=pretty --test-threads=1 "$@" 2>&1 | python3 -u -c '
import sys, time
for line in sys.stdin:
    sys.stdout.write(f"{time.time():.6f} {line}")
' | tee "$raw"
status=${PIPESTATUS[0]}
set -e

python3 - "$suite" "$raw" "$XML_OUTPUT_FILE" <<'PY'
import re
import sys
from xml.sax.saxutils import escape

suite, raw_path, xml_path = sys.argv[1:]

ts_re = re.compile(r"^(?P<ts>\d+\.\d+) (?P<rest>.*)$")
case_re = re.compile(r"^test (?P<name>.+?) \.\.\. (?P<result>ok|FAILED|ignored)\b")
running_re = re.compile(r"^running \d+ tests?\b")
failure_hdr_re = re.compile(r"^---- (?P<name>.+?) stdout ----")

cases = []  # (name, result, duration_seconds)
failures = {}
current_fail = None
last_ts = None  # wall clock of the previous case's completion line

with open(raw_path, "r", errors="replace") as fh:
    for line in fh:
        tsm = ts_re.match(line)
        if not tsm:
            # A rare unprefixed line (child process, panic-only) does not
            # affect timing: only prefixed completion lines advance last_ts.
            payload = line.rstrip("\n")
            ts = None
        else:
            ts = float(tsm.group("ts"))
            payload = tsm.group("rest").rstrip("\n")

        if running_re.match(payload):
            last_ts = ts
            continue

        m = case_re.match(payload)
        if m:
            name = m.group("name")
            result = m.group("result")
            if ts is not None and last_ts is not None:
                duration = max(ts - last_ts, 0.0)
            else:
                duration = 0.0
            cases.append((name, result, duration))
            if ts is not None:
                last_ts = ts
            current_fail = None
            continue

        m = failure_hdr_re.match(payload)
        if m:
            current_fail = m.group("name")
            failures[current_fail] = []
            continue

        if current_fail is not None:
            if payload.startswith("failures:") or payload.startswith("test result:"):
                current_fail = None
            else:
                failures[current_fail].append(payload)

def testcase(name, result, duration):
    body = ""
    if result == "FAILED":
        msg = "\n".join(failures.get(name, [])).strip() or "test failed"
        body = f'<failure message="test failed">{escape(msg)}</failure>'
    elif result == "ignored":
        body = '<skipped/>'
    return f'    <testcase name="{escape(name)}" classname="{escape(suite)}" time="{duration:.6f}">{body}</testcase>'

total = len(cases)
failed = sum(1 for _, r, _ in cases if r == "FAILED")
skipped = sum(1 for _, r, _ in cases if r == "ignored")

with open(xml_path, "w") as out:
    out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
    out.write('<testsuites>\n')
    out.write(
        f'  <testsuite name="{escape(suite)}" tests="{total}" failures="{failed}" skipped="{skipped}">\n'
    )
    for name, result, duration in cases:
        out.write(testcase(name, result, duration) + "\n")
    out.write('  </testsuite>\n')
    out.write('</testsuites>\n')
PY

exit "$status"
