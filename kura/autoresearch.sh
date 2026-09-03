#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --cache_test_results=no \
  --test_arg=http_response_admission_metric_handles_benchmark \
  --test_arg=--ignored \
  --test_arg=--nocapture \
  --test_output=streamed
