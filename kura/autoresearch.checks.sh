#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=successful_reapi_writes_use_the_registered_metric_series \
  --test_output=errors
