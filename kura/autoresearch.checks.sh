#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=backfill_bodies_reclaim_spool_files \
  --test_output=errors
