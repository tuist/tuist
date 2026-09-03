#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=a_shed_write_is_counted_as_a_capacity_shed \
  --test_output=errors
