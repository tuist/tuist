#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --cache_test_results=no \
  --test_arg=segment_reader_blocking_dispatch_benchmark \
  --test_arg=--ignored \
  --test_arg=--nocapture \
  --test_output=streamed
