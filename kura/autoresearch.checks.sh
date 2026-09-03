#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=digest_comparison_accepts_exact_bytes_and_rejects_invalid_hashes \
  --test_output=errors
