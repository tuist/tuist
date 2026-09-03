#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=positioned \
  --test_output=errors

mise exec -- bazel test //:kura_lib_test \
  --test_arg=concurrent_artifact_writes_batch_segment_fsyncs \
  --test_output=errors
