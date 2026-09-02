#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --cache_test_results=no \
  --test_arg=artifact_reader_inline_bytes_stream_benchmark \
  --test_arg=--ignored \
  --test_arg=--nocapture \
  --test_output=streamed
