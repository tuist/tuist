#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=bytestream_read_response_stream_preserves_bytes_and_chunk_bound \
  --test_output=errors
