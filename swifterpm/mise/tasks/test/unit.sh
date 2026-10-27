#!/usr/bin/env bash
#MISE description="Run Swift unit tests. Extra arguments are forwarded to bazel test."
set -euo pipefail

bazel test --test_output=all "$@" //:swifterpm_tests
