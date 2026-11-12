#!/usr/bin/env bash
# Configures the Tuist remote cache for the Bazel workspace in the current directory and, when the
# account has Linux remote execution capacity, the remote executor too. Without capacity (flag off,
# no worker with a ready template, no cache) setup warns and stays cache-only, so a merge never
# waits on remote execution being available.
set -euo pipefail

tuist auth login
tuist bazel setup --remote-execution

# A workspace that defines this config registers the execution environment's toolchains with it,
# which only work when actions run remotely.
executor=$(sed -n 's/^build --remote_executor=//p' .bazelrc.tuist 2>/dev/null | tail -n 1 || true)
if [ -z "$executor" ]; then
  echo "::notice title=Bazel remote execution::off; actions build on this runner with the Tuist remote cache"
elif grep -q '^build:tuist-remote-execution ' .bazelrc 2>/dev/null; then
  echo "build --config=tuist-remote-execution" >>.bazelrc.tuist
  echo "::notice title=Bazel remote execution::on via $executor with --config=tuist-remote-execution"
else
  echo "::notice title=Bazel remote execution::on via $executor"
fi
