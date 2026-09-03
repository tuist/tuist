#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=metrics_handle_is_one_shared_reference \
  --test_output=errors
