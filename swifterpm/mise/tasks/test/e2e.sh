#!/usr/bin/env bash
#MISE description="Run end-to-end resolver tests against real-world Package.swift fixtures"
set -euo pipefail

bazel build //:swifterpm
shellspec_args=(--shell bash)
shellspec_jobs="${SHELLSPEC_JOBS:-6}"
if [[ "${shellspec_jobs}" != "0" ]]; then
  shellspec_args+=(--jobs "${shellspec_jobs}")
fi

SWIFTERPM_BIN="${PWD}/bazel-bin/swifterpm" shellspec "${shellspec_args[@]}" e2e
