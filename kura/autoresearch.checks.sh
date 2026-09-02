#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=inline_bytes_stream_reuses \
  --test_output=errors
