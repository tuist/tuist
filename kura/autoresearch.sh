#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --cache_test_results=no \
  --test_arg=accelerated_setup_ownership_benchmark \
  --test_arg=--ignored \
  --test_arg=--nocapture \
  --test_output=streamed
