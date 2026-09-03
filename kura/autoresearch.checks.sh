#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=replicated_path_apply_preserves_the_staged_file_cache_policy \
  --test_output=errors
