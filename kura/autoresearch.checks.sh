#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=bytestream_read_response_ \
  --test_output=errors
