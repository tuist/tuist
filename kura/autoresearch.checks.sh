#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=bytestream_write_latency_uses_the_registered_metric_series \
  --test_output=errors
