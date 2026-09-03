#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=request_path_writes_also_commit_off_the_runtime_worker \
  --test_output=errors
