#!/usr/bin/env bash

# Mixed-version rollout compatibility harness.
#
# MANUAL PRE-RELEASE GATE — no CI workflow runs this script (it builds two
# Docker images from git refs, which is too expensive for the PR loop). Run it
# before tagging any Kura release, with PREVIOUS_REF set to the previously
# released ref:
#
#   PREVIOUS_REF=origin/main kura/test/e2e/kura_compatibility_rollout.sh
#
# Stages, for the push-removal ladder. PREVIOUS_REF is expected to be the
# last release that still carried the push path (its pods run with
# KURA_REPLICATION_PULL=true, which is what the fleet was at when the push
# path was removed); CURRENT_REF pulls only:
#
#   0. previous <-> current rolling update and rollback: both directions
#      converge and the dataset survives, so the rollout can be reverted in
#      place.
#   1. previous -> current one node at a time: the current node pulls from
#      its previous-release peer and is pulled by it, both catch-ups settle,
#      the rollout gate stays green across the overlap, and the current node
#      still answers the push receivers a peer that predates pull needs.
#   2. cold-node convergence across the skew, both directions: a cold
#      previous-release peer catches up from a current node and a cold
#      current node catches up from a previous-release peer.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREVIOUS_REF="${PREVIOUS_REF:-}"
CURRENT_REF="${CURRENT_REF:-HEAD}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-kura-compat}"
KURA_US_PORT="${KURA_US_PORT:-4701}"
KURA_EU_PORT="${KURA_EU_PORT:-4702}"
PREVIOUS_IMAGE="${PREVIOUS_IMAGE:-kura-compat-previous:latest}"
CURRENT_IMAGE="${CURRENT_IMAGE:-kura-compat-current:latest}"
PREVIOUS_WORKTREE_CANONICAL=""

export KURA_US_PORT KURA_EU_PORT

if [[ -z "${PREVIOUS_REF}" ]]; then
  echo "Set PREVIOUS_REF to the adjacent version ref to validate, for example PREVIOUS_REF=origin/main" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kura-compat.XXXXXX")"
PREVIOUS_WORKTREE="${TMP_DIR}/previous"
PREVIOUS_OVERRIDE="${TMP_DIR}/compose.previous.yml"
SKEW_OVERRIDE="${TMP_DIR}/compose.skew.yml"
CURRENT_OVERRIDE="${TMP_DIR}/compose.current.yml"

cleanup() {
  local registered_worktree="${PREVIOUS_WORKTREE_CANONICAL:-${PREVIOUS_WORKTREE}}"
  docker compose -p "${COMPOSE_PROJECT_NAME}" \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    -f "${PREVIOUS_OVERRIDE}" \
    down -v --remove-orphans >/dev/null 2>&1 || true
  if git -C "${PROJECT_ROOT}" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${registered_worktree}\$"; then
    git -C "${PROJECT_ROOT}" worktree remove --force "${registered_worktree}" >/dev/null 2>&1 || true
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
  PREVIOUS_WORKTREE_CANONICAL="$(cd "${context_dir}" && pwd -P)"
  docker build -t "${image}" "${context_dir}/kura"
}

# Renders a compose override pinning each node's image. KURA_REPLICATION_PULL
# and KURA_BACKFILL_ENABLED are rendered for the previous release, which still
# reads them (the fleet ran flag-on when the push path was removed, and a
# flag-off previous node would only ever be pushed to, which nothing does any
# more); the current binary ignores both. KURA_PEERS is trimmed to the
# two harness nodes so the never-started kura-ap cannot enter a node's initial
# backfill cycle — its connection failures would drain the failure budget and
# degrade the cycle mode for reasons unrelated to the ladder under test.
# KURA_CAS_CAPACITY_BYTES=1 clamps both rings to the 5-segment floor: without
# it the ring total derives from the host's disk size, one written segment
# rounds to 0% fullness, and a pod whose initial cycle is still pending mid
# skew could never latch readiness via the ring-fullness clause (1 of 5
# segments = 20% = the default threshold).
write_override() {
  local path="$1"
  local kura_us_image="$2"
  local kura_eu_image="$3"
  local kura_us_flag="${4:-true}"
  local kura_eu_flag="${5:-true}"

  cat >"${path}" <<EOF
services:
  kura-us:
    build: null
    image: ${kura_us_image}
    pull_policy: never
    environment:
      KURA_BACKFILL_ENABLED: "${kura_us_flag}"
      KURA_REPLICATION_PULL: "true"
      KURA_CAS_CAPACITY_BYTES: "1"
      KURA_PEERS: http://kura-us.kura.internal:7443,http://kura-eu.kura.internal:7443
  kura-eu:
    build: null
    image: ${kura_eu_image}
    pull_policy: never
    environment:
      KURA_BACKFILL_ENABLED: "${kura_eu_flag}"
      KURA_REPLICATION_PULL: "true"
      KURA_CAS_CAPACITY_BYTES: "1"
      KURA_PEERS: http://kura-us.kura.internal:7443,http://kura-eu.kura.internal:7443
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

wait_for_rollout_contains() {
  local url="$1"
  local needle="$2"
  local attempts="${3:-90}"

  for _ in $(seq 1 "${attempts}"); do
    local body
    body="$(curl -fsS "${url}/status/rollout" 2>/dev/null || true)"
    if [[ "${body}" == *"${needle}"* ]]; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for ${needle} in ${url}/status/rollout" >&2
  return 1
}

# Asserts an internal route is still served. Internal routes live on the
# peer listener (7443), which compose does not publish, so the probe runs
# inside the container; a route that is gone is a plain 404 from axum's
# fallback rather than a connection error.
assert_route_present() {
  local override="$1"
  local service="$2"
  local path="$3"
  local status
  status="$(dc "${override}" exec -T "${service}" \
    curl -s -o /dev/null -w '%{http_code}' -X PUT "http://localhost:7443${path}")"
  if [[ "${status}" == "404" || "${status}" == "405" || -z "${status}" ]]; then
    echo "Expected ${service}:7443${path} to still be served for pre-pull peers, got '${status}'" >&2
    return 1
  fi
}

# Sums a labeled counter family scraped from URL/metrics; FILTER is a label
# substring the sample must carry. Tolerates the prometheus_client crate's
# extra `_total` counter suffix on top of the registered name.
metric_sum() {
  local url="$1" metric="$2" filter="${3:-}"
  curl -fsS "${url}/metrics" 2>/dev/null | awk -v metric="$metric" -v filter="$filter" '
    index($0, metric) == 1 {
      rest = substr($0, length(metric) + 1)
      sub(/^_total/, "", rest)
      tail = substr(rest, 1, 1)
      if (tail != "{" && tail != " ") { next }
      if (filter != "" && index($0, filter) == 0) { next }
      sum += $NF
    }
    END { printf "%.0f", sum + 0 }'
}

wait_for_metric_ge() {
  local url="$1" metric="$2" filter="$3" threshold="$4" attempts="${5:-90}"
  local value

  for _ in $(seq 1 "${attempts}"); do
    value="$(metric_sum "${url}" "${metric}" "${filter}")"
    if [[ "${value:-0}" -ge "${threshold}" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for ${metric}{${filter}} on ${url} to reach ${threshold} (last ${value:-0})" >&2
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

# Recreates SERVICE with an empty data volume under the given override, so its
# next boot is a genuine cold join against whatever the other node serves.
recreate_service_cold() {
  local override="$1"
  local service="$2"
  local volume="$3"

  dc "${override}" rm -sf "${service}" >/dev/null 2>&1
  docker volume rm "${COMPOSE_PROJECT_NAME}_${volume}" >/dev/null
  dc "${override}" up -d "${service}" >/dev/null
}

# gate.sh transport + wrapper: the harness applies the fleet rollout gate's
# per-node clauses (ready, serving, expected ring size, no critical memory
# pressure, and backfill_initial_cycle != pending) using gate.sh's own
# parsers. The one clause it cannot apply is cross-node
# `generation` agreement: that value is a node-local membership-view counter
# that only converges when the control plane publishes a shared view, so
# under compose DNS discovery two healthy nodes report different generations
# forever and rollout_wait_for_gate would never return.
node_rollout_status_get() {
  curl -fsS "$1/status/rollout"
}

# shellcheck source=../../ops/rollout/gate.sh
source "${PROJECT_ROOT}/ops/rollout/gate.sh"

assert_gate_green() {
  local expected_ring_members=2
  local deadline=$((SECONDS + 300))
  local steady_needed=2

  while ((SECONDS < deadline)); do
    local ok=1 steady=0
    local node body ready state ring_members pressure backfill_mode

    while ((steady < steady_needed)); do
      ok=1
      for node in "$@"; do
        if ! body="$(rollout_collect_status_with_retry "${node}")"; then
          ok=0
          break
        fi
        # Not rollout_json_bool: its sed alternation is a GNU extension and
        # matches nothing under BSD sed, and this harness is a manual gate
        # that must run on developer macOS too.
        ready="false"
        [[ "${body}" == *'"ready":true'* ]] && ready="true"
        state="$(rollout_json_string "${body}" "state")"
        ring_members="$(rollout_json_number "${body}" "ring_members")"
        backfill_mode="$(rollout_json_string "${body}" "backfill_initial_cycle")"
        pressure="$(rollout_json_number "${body}" "memory_pressure_state")"

        [ "${ready:-false}" = "true" ] || ok=0
        [ "${state:-unknown}" = "serving" ] || ok=0
        [ "${ring_members:-0}" = "${expected_ring_members}" ] || ok=0
        [ "${backfill_mode:-complete}" != "pending" ] || ok=0
        [ "${pressure:-0}" != "2" ] || ok=0
      done
      if [ "${ok}" = "1" ]; then
        steady=$((steady + 1))
        sleep 2
      else
        break
      fi
    done

    if ((steady >= steady_needed)); then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for the rollout gate clauses on: $*" >&2
  return 1
}

stage_0_rolling_update_and_rollback() {
  local us_url="$1"
  local eu_url="$2"

  echo "--- stage 0: previous <-> current rolling update and rollback"

  dc "${PREVIOUS_OVERRIDE}" down -v --remove-orphans >/dev/null 2>&1 || true
  dc "${PREVIOUS_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  put_artifact "${us_url}" "artifact-v1" "payload-from-previous"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v1")" "payload-from-previous"

  dc "${CURRENT_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  put_artifact "${us_url}" "artifact-v2" "payload-from-current"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v2")" "payload-from-current"

  # Rolling back must find its data intact: the current binary writes
  # nothing the previous one cannot read, and the arrival feed, cursors and
  # watermarks it left behind are the same durable rows the previous release
  # already maintains. The outbox column family it swept stays declared.
  dc "${PREVIOUS_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  wait_for_body "$(artifact_url "${us_url}" "artifact-v1")" "payload-from-previous"
  wait_for_body "$(artifact_url "${us_url}" "artifact-v2")" "payload-from-current"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v1")" "payload-from-previous"
  wait_for_body "$(artifact_url "${eu_url}" "artifact-v2")" "payload-from-current"

  echo "stage 0 passed"
}

stage_1_previous_to_current_rolling_update() {
  local us_url="$1"
  local eu_url="$2"

  echo "--- stage 1: previous -> current rolling update, one node at a time"

  dc "${PREVIOUS_OVERRIDE}" down -v --remove-orphans >/dev/null 2>&1 || true
  dc "${PREVIOUS_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair
  put_artifact "${us_url}" "skew-w1" "skew-payload-1"
  wait_for_body "$(artifact_url "${eu_url}" "skew-w1")" "skew-payload-1"
  assert_gate_green "${us_url}" "${eu_url}"

  # Upgrade kura-us only: a pull-only node beside a previous-release peer
  # that pulls and still carries the push path. Both pull from each other;
  # the previous peer advertises `pulling`, so it pushes nothing here.
  dc "${SKEW_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair
  wait_for_rollout_contains "${us_url}" '"backfill_initial_cycle":"complete"'
  wait_for_rollout_contains "${eu_url}" '"backfill_initial_cycle":"complete"'
  assert_gate_green "${us_url}" "${eu_url}"

  # The push receivers stay on the current node for peers that predate
  # pull: the route answers (400 on an empty query, never 404).
  assert_route_present "${SKEW_OVERRIDE}" kura-us "/_internal/replicate/artifact"

  # Bidirectional convergence across the skew: replication is version-agnostic.
  put_artifact "${us_url}" "skew-w2" "skew-payload-2"
  wait_for_body "$(artifact_url "${eu_url}" "skew-w2")" "skew-payload-2"
  put_artifact "${eu_url}" "skew-w3" "skew-payload-3"
  wait_for_body "$(artifact_url "${us_url}" "skew-w3")" "skew-payload-3"

  # Complete the rolling update.
  dc "${CURRENT_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair
  wait_for_rollout_contains "${us_url}" '"backfill_initial_cycle":"complete"'
  wait_for_rollout_contains "${eu_url}" '"backfill_initial_cycle":"complete"'
  assert_gate_green "${us_url}" "${eu_url}"

  put_artifact "${eu_url}" "skew-w4" "skew-payload-4"
  wait_for_body "$(artifact_url "${us_url}" "skew-w4")" "skew-payload-4"

  echo "stage 1 passed"
}

stage_2_cold_convergence_across_the_skew() {
  local us_url="$1"
  local eu_url="$2"

  echo "--- stage 2: cold nodes converge in both directions across the skew"

  dc "${SKEW_OVERRIDE}" down -v --remove-orphans >/dev/null 2>&1 || true
  dc "${SKEW_OVERRIDE}" up -d kura-us >/dev/null
  wait_for_http "${us_url}/ready"
  put_artifact "${us_url}" "mixed-h1" "mixed-payload-1"

  # Cold previous-release peer catches up from the current node through the
  # backfill listing and the feed, both of which it already speaks.
  dc "${SKEW_OVERRIDE}" up -d kura-eu >/dev/null
  wait_for_ready_pair
  wait_for_body "$(artifact_url "${eu_url}" "mixed-h1")" "mixed-payload-1"
  # The body alone does not prove the catch-up ran through a pass; assert
  # the requester actually applied a body through one, or a broken catch-up
  # path across the skew passes this stage unnoticed.
  wait_for_metric_ge "${eu_url}" "kura_backfill_bodies_total" 'outcome="applied"' 1

  put_artifact "${eu_url}" "mixed-h2" "mixed-payload-2"
  wait_for_body "$(artifact_url "${us_url}" "mixed-h2")" "mixed-payload-2"

  # Cold current node catches up from the previous-release peer.
  recreate_service_cold "${SKEW_OVERRIDE}" kura-us kura-us-data
  wait_for_ready_pair
  wait_for_body "$(artifact_url "${us_url}" "mixed-h1")" "mixed-payload-1"
  wait_for_body "$(artifact_url "${us_url}" "mixed-h2")" "mixed-payload-2"
  # Both entries predate this node's volume, so both had to arrive through a
  # pass against the previous-release peer.
  wait_for_metric_ge "${us_url}" "kura_backfill_bodies_total" 'outcome="applied"' 2
  wait_for_rollout_contains "${us_url}" '"backfill_initial_cycle":"complete"'
  assert_gate_green "${us_url}" "${eu_url}"

  echo "stage 2 passed"
}

main() {
  local us_url="http://127.0.0.1:${KURA_US_PORT}"
  local eu_url="http://127.0.0.1:${KURA_EU_PORT}"

  build_image_from_ref "${PREVIOUS_REF}" "${PREVIOUS_IMAGE}" "${PREVIOUS_WORKTREE}"
  build_image_from_ref "${CURRENT_REF}" "${CURRENT_IMAGE}" "${PROJECT_ROOT}"

  write_override "${PREVIOUS_OVERRIDE}" "${PREVIOUS_IMAGE}" "${PREVIOUS_IMAGE}"
  write_override "${SKEW_OVERRIDE}" "${CURRENT_IMAGE}" "${PREVIOUS_IMAGE}"
  write_override "${CURRENT_OVERRIDE}" "${CURRENT_IMAGE}" "${CURRENT_IMAGE}"

  stage_0_rolling_update_and_rollback "${us_url}" "${eu_url}"
  stage_1_previous_to_current_rolling_update "${us_url}" "${eu_url}"
  stage_2_cold_convergence_across_the_skew "${us_url}" "${eu_url}"

  echo "Compatibility rollout passed for ${PREVIOUS_REF} -> ${CURRENT_REF}"
}

main
