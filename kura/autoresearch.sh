#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --cache_test_results=no \
  --test_arg=existence_cache_shared_key_benchmark \
  --test_arg=--ignored \
  --test_arg=--nocapture \
  --test_output=streamed
