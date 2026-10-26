#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "get" || -z "${SWIFTERPM_E2E_GIT_TOKEN:-}" ]]; then
  exit 0
fi

protocol=""
host=""
while IFS='=' read -r key value && [[ -n "${key}" ]]; do
  case "${key}" in
    protocol) protocol="${value}" ;;
    host) host="${value}" ;;
  esac
done

if [[ "${protocol}" == "https" && "${host}" == "github.com" ]]; then
  printf '%s\n' 'username=x-access-token' "password=${SWIFTERPM_E2E_GIT_TOKEN}"
fi
