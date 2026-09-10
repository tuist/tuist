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
# match. Threading is left at the harness default: libtest writes one full
# line per case atomically, so parallel runs are safe to parse.
set +e
"$binary" --format=pretty "$@" | tee "$raw"
status=${PIPESTATUS[0]}
set -e

python3 - "$suite" "$raw" "$XML_OUTPUT_FILE" <<'PY'
import re
import sys
from xml.sax.saxutils import escape

suite, raw_path, xml_path = sys.argv[1:]

case_re = re.compile(r"^test (?P<name>.+?) \.\.\. (?P<result>ok|FAILED|ignored)\b")
# Failure blocks in the "failures:" section carry the stdout/panic message.
failure_hdr_re = re.compile(r"^---- (?P<name>.+?) stdout ----")

cases = []
failures = {}
current_fail = None

with open(raw_path, "r", errors="replace") as fh:
    lines = fh.read().splitlines()

for line in lines:
    m = case_re.match(line)
    if m:
        cases.append((m.group("name"), m.group("result")))
        current_fail = None
        continue
    m = failure_hdr_re.match(line)
    if m:
        current_fail = m.group("name")
        failures[current_fail] = []
        continue
    # Stop appending to a failure block when libtest starts the summary.
    if current_fail is not None:
        if line.startswith("failures:") or line.startswith("test result:"):
            current_fail = None
        else:
            failures[current_fail].append(line)

def testcase(name, result):
    body = ""
    if result == "FAILED":
        msg = "\n".join(failures.get(name, [])).strip() or "test failed"
        body = f'<failure message="test failed">{escape(msg)}</failure>'
    elif result == "ignored":
        body = '<skipped/>'
    # No per-case duration on stable libtest without unstable flags; leave 0.
    return f'    <testcase name="{escape(name)}" classname="{escape(suite)}" time="0">{body}</testcase>'

total = len(cases)
failed = sum(1 for _, r in cases if r == "FAILED")
skipped = sum(1 for _, r in cases if r == "ignored")

with open(xml_path, "w") as out:
    out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
    out.write('<testsuites>\n')
    out.write(
        f'  <testsuite name="{escape(suite)}" tests="{total}" failures="{failed}" skipped="{skipped}">\n'
    )
    for name, result in cases:
        out.write(testcase(name, result) + "\n")
    out.write('  </testsuite>\n')
    out.write('</testsuites>\n')
PY

exit "$status"
