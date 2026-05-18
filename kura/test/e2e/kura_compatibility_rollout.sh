#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREVIOUS_REF="${PREVIOUS_REF:-}"
CURRENT_REF="${CURRENT_REF:-HEAD}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-kura-compat}"
KURA_US_PORT="${KURA_US_PORT:-4701}"
KURA_EU_PORT="${KURA_EU_PORT:-4702}"
PREVIOUS_IMAGE="${PREVIOUS_IMAGE:-kura-compat-previous:latest}"
CURRENT_IMAGE="${CURRENT_IMAGE:-kura-compat-current:latest}"

if [[ -z "${PREVIOUS_REF}" ]]; then
  echo "Set PREVIOUS_REF to the adjacent version ref to validate, for example PREVIOUS_REF=origin/main" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kura-compat.XXXXXX")"
PREVIOUS_WORKTREE="${TMP_DIR}/previous"
PREVIOUS_OVERRIDE="${TMP_DIR}/compose.previous.yml"
MIXED_OVERRIDE="${TMP_DIR}/compose.mixed.yml"

cleanup() {
  docker compose -p "${COMPOSE_PROJECT_NAME}" \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    -f "${PREVIOUS_OVERRIDE}" \
    down -v --remove-orphans >/dev/null 2>&1 || true
  if git -C "${PROJECT_ROOT}" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${PREVIOUS_WORKTREE}\$"; then
    git -C "${PROJECT_ROOT}" worktree remove --force "${PREVIOUS_WORKTREE}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

dc() {
  docker compose -p "${COMPOSE_PROJECT_NAME}" \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    -f "$1" \
    "${@:2}"
}

build_image_from_ref() {
  local ref="$1"
  local image="$2"
  local context_dir="$3"

  if [[ "${ref}" == "${CURRENT_REF}" ]]; then
    docker build -t "${image}" "${PROJECT_ROOT}"
    return
  fi

  git -C "${PROJECT_ROOT}" worktree add --detach "${context_dir}" "${ref}" >/dev/null
  docker build -t "${image}" "${context_dir}"
}

write_override() {
  local path="$1"
  local kura_us_image="$2"
  local kura_eu_image="$3"

  cat >"${path}" <<EOF
services:
  kura-us:
    build: null
    image: ${kura_us_image}
    pull_policy: never
  kura-eu:
    build: null
    image: ${kura_eu_image}
    pull_policy: never
EOF
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-90}"

  for _ in $(seq 1 "${attempts}"); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for ${url}" >&2
  return 1
}

wait_for_body() {
  local url="$1"
  local expected="$2"
  local attempts="${3:-90}"

  for _ in $(seq 1 "${attempts}"); do
    local body
    body="$(curl -fsS "${url}" 2>/dev/null || true)"
    if [[ "${body}" == "${expected}" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for ${expected} from ${url}" >&2
  return 1
}

put_artifact() {
  local url="$1"
  local artifact_id="$2"
  local payload="$3"
  curl -fsS -X POST \
    "${url}/api/cache/cas/${artifact_id}?tenant_id=acme&namespace_id=ios" \
    -H "content-type: application/octet-stream" \
    --data-binary "${payload}" >/dev/null
}

artifact_url() {
  local base_url="$1"
  local artifact_id="$2"
  printf '%s/api/cache/cas/%s?tenant_id=acme&namespace_id=ios' "${base_url}" "${artifact_id}"
}

wait_for_ready_pair() {
  wait_for_http "http://127.0.0.1:${KURA_US_PORT}/ready"
  wait_for_http "http://127.0.0.1:${KURA_EU_PORT}/ready"
}

main() {
  local us_url="http://127.0.0.1:${KURA_US_PORT}"
  local eu_url="http://127.0.0.1:${KURA_EU_PORT}"

  build_image_from_ref "${PREVIOUS_REF}" "${PREVIOUS_IMAGE}" "${PREVIOUS_WORKTREE}"
  build_image_from_ref "${CURRENT_REF}" "${CURRENT_IMAGE}" "${PROJECT_ROOT}"

  write_override "${PREVIOUS_OVERRIDE}" "${PREVIOUS_IMAGE}" "${PREVIOUS_IMAGE}"
  write_override "${MIXED_OVERRIDE}" "${CURRENT_IMAGE}" "${PREVIOUS_IMAGE}"

  dc "${PREVIOUS_OVERRIDE}" down -v --remove-orphans >/dev/null 2>&1 || true
  dc "${PREVIOUS_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  put_artifact "${us_url}" "artifact-v1" "payload-from-previous"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v1")" "payload-from-previous"

  dc "${MIXED_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  put_artifact "${us_url}" "artifact-v2" "payload-from-current"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v2")" "payload-from-current"

  dc "${PREVIOUS_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  wait_for_body "$(artifact_url "${us_url}" "artifact-v1")" "payload-from-previous"
  wait_for_body "$(artifact_url "${us_url}" "artifact-v2")" "payload-from-current"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v1")" "payload-from-previous"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v2")" "payload-from-current"

  echo "Compatibility rollout passed for ${PREVIOUS_REF} -> ${CURRENT_REF} -> ${PREVIOUS_REF}"
}

main
