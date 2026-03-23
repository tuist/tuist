#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="${MISE_PROJECT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
INSTANCE_FILE="${PROJECT_ROOT}/.tuist-dev-instance"

validate_suffix() {
  local suffix="$1"

  [[ "$suffix" =~ ^[0-9]+$ ]] || return 1
  (( suffix >= 1 && suffix <= 999 ))
}

if [[ -n "${TUIST_DEV_INSTANCE:-}" ]]; then
  validate_suffix "${TUIST_DEV_INSTANCE}" || {
    echo "TUIST_DEV_INSTANCE must be an integer between 1 and 999" >&2
    exit 1
  }

  printf '%s' "${TUIST_DEV_INSTANCE}" > "${INSTANCE_FILE}"
  exit 0
fi

if [[ -s "${INSTANCE_FILE}" ]]; then
  existing_suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"

  validate_suffix "${existing_suffix}" || {
    echo "Invalid suffix in ${INSTANCE_FILE}. Expected an integer between 1 and 999." >&2
    exit 1
  }

  exit 0
fi

random_suffix="$(awk 'BEGIN { srand(); print int(100 + rand() * 900) }')"
printf '%s' "${random_suffix}" > "${INSTANCE_FILE}"
