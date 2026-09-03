#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel test //:kura_lib_test \
  --test_arg=parses_read_resource_names_with_and_without_instance_names \
  --test_output=errors
