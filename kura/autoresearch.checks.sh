#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=backfill_spool_owned_chunks_preserve_bytes \
  --test_output=errors
