#!/usr/bin/env bash
#MISE description="Run end-to-end resolver tests against real-world Package.swift fixtures. Extra arguments are forwarded to bazel build."
set -euo pipefail

bazel build "$@" //:swifterpm
shellspec_args=(--shell bash)
shellspec_jobs="${SHELLSPEC_JOBS:-6}"
if [[ "${shellspec_jobs}" != "0" ]]; then
  shellspec_args+=(--jobs "${shellspec_jobs}")
fi

if [[ -n "${SWIFTERPM_E2E_GIT_TOKEN:-}" ]]; then
  git_config_count="${GIT_CONFIG_COUNT:-0}"
  export "GIT_CONFIG_KEY_${git_config_count}=credential.https://github.com.helper"
  export "GIT_CONFIG_VALUE_${git_config_count}=!bash \"${PWD}/e2e/github-credential-helper.sh\""
  export "GIT_CONFIG_KEY_$((git_config_count + 1))=http.https://github.com/.proactiveAuth"
  export "GIT_CONFIG_VALUE_$((git_config_count + 1))=basic"
  export GIT_CONFIG_COUNT="$((git_config_count + 2))"
fi

SWIFTERPM_BIN="${PWD}/bazel-bin/swifterpm" shellspec "${shellspec_args[@]}" e2e
