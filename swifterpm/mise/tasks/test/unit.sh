#!/usr/bin/env bash
#MISE description="Run Swift unit tests"
set -euo pipefail

bazel test --test_output=all //:swifterpm_tests
