#!/usr/bin/env bash
#MISE description="Build kura with Bazel (bazel build //...). Pass extra bazel flags through, e.g. mise run compile -- -c opt. Use --binary-only to build just the release binary."
#USAGE flag "--binary-only" help="Build only the release binary //:kura instead of all targets (//...). //:kura omits the test target, which can't cross-compile — the release pipeline uses this."
#USAGE arg "[bazel_args]" var=#true help="Extra flags forwarded verbatim to bazel build"
set -euo pipefail

# usage validates the args and sets $usage_binary_only; the raw args stay in "$@" (its own
# capture variable mangles --flag=value pairs). Forward every token except the consumed
# --binary-only (and a passthrough --). A word-split string keeps this bash-3.2 safe — empty
# arrays are an unbound-variable footgun there under `set -u`.
bazel_args=""
for arg in "$@"; do
  case "$arg" in
  --binary-only | --) ;;
  *) bazel_args="${bazel_args:+$bazel_args }$arg" ;;
  esac
done

target="//..."
[ "${usage_binary_only:-false}" = "true" ] && target="//:kura"

# No `cd` needed: mise runs file tasks from the config root (kura/), where the bazel workspace
# resolves.
# shellcheck disable=SC2086 # intentional word-splitting of the collected bazel flags
bazel build "$target" $bazel_args

echo "✔ kura binary: $(pwd)/bazel-bin/kura"
