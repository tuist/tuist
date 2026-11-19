#!/usr/bin/env bash
# Run stable libtest with structured per-case events, then emit JUnit with the
# Rust reporter. Preserve public suite identity, failures, ignored cases and
# durations without requiring Python or parsing interleaved human output.
# Invocation: <test-binary> <public-suite-name> <reporter> [libtest args...]
# TESTBRIDGE_TEST_ONLY is not translated: use --test_arg for libtest filters.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "rust_libtest_junit.sh: expected binary, suite and reporter" >&2
  exit 2
fi
binary=$1
suite=$2
reporter=$3
shift 3

if [[ ! -x $binary && -n ${RUNFILES_DIR:-} && -x $RUNFILES_DIR/$binary ]]; then
  binary=$RUNFILES_DIR/$binary
fi
if [[ ! -x $reporter && -n ${RUNFILES_DIR:-} && -x $RUNFILES_DIR/$reporter ]]; then
  reporter=$RUNFILES_DIR/$reporter
fi
raw=${TEST_TMPDIR:-/tmp}/${suite}.raw.log

set +e
RUSTC_BOOTSTRAP=1 "$binary" -Z unstable-options --format json --report-time "$@" | tee "$raw"
statuses=("${PIPESTATUS[@]}")
status=${statuses[0]}
if [[ $status -eq 0 && ${statuses[1]} -ne 0 ]]; then
  status=${statuses[1]}
fi
set -e

"$reporter" "$suite" "$raw" "${XML_OUTPUT_FILE:?JUnit output path is required}"
exit "$status"
