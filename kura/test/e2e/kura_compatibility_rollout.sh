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
# Stages (docs/plans/2026-07-30-001-refactor-kura-backfill-plan.md, Unit 11):
#
#   0. previous <-> current flag-off rolling update and rollback — the
#      Release AB deploy itself is behavior-neutral and rollback needs no
#      preparation (backfill/ index rows are inert dead keys to the previous
#      binary).
#   1. old -> AB rolling update with KURA_BACKFILL_ENABLED=true on the AB
#      pods: the flag-on pod retries the not-capable class against the old
#      peer (capped by the compiled BACKFILL_RETRYABLE_WAIT_CAP_MS = 30 min),
#      old pods bootstrap from AB via the retained legacy serving, and the
#      rollout gate is green once the update completes. During the skew
#      window itself the flag-on pod reports backfill_initial_cycle=pending —
#      the gate intentionally holds there, so the harness asserts readiness
#      and bidirectional convergence during the window and gate-green before
#      and after it, rather than sleeping out the 30-minute cap.
#   2. mixed-flag mesh: flag-on and flag-off AB pods converge in both
#      directions — a cold flag-off pod legacy-bootstraps from a flag-on
#      peer, and a cold flag-on pod backfills from a flag-off peer via the
#      unconditional serving plane.
#   3. AB -> C: TODO stage stub — Release C (Units 10 + 12) does not exist
#      yet. When it does, this stage must assert that C peers serve flag-on
#      AB peers via the new endpoints only (legacy serving deleted) and that
#      gate.sh stays green across the AB -> C overlap.

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
MIXED_OVERRIDE="${TMP_DIR}/compose.mixed.yml"
FLAG_ON_SKEW_OVERRIDE="${TMP_DIR}/compose.flag-on-skew.yml"
FLAG_ON_OVERRIDE="${TMP_DIR}/compose.flag-on.yml"
MIXED_FLAG_OVERRIDE="${TMP_DIR}/compose.mixed-flag.yml"

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

# Renders a compose override pinning each node's image and its
# KURA_BACKFILL_ENABLED value. KURA_PEERS is trimmed to the two harness nodes
# so the never-started kura-ap cannot enter a flag-on node's initial backfill
# cycle (its connection failures would drain the failure budget and degrade
# the cycle mode for reasons unrelated to the ladder under test). The previous
# binary ignores the flag env entirely. KURA_CAS_CAPACITY_BYTES=1 clamps both
# rings to the 5-segment floor: without it the ring total derives from the
# host's disk size, one written segment rounds to 0% fullness, and the
# flag-on pod in the stage-1 skew window — whose initial cycle cannot settle
# against a not-capable old peer — could never latch readiness via the
# ring-fullness clause (1 of 5 segments = 20% = the default threshold).
write_override() {
  local path="$1"
  local kura_us_image="$2"
  local kura_eu_image="$3"
  local kura_us_flag="${4:-false}"
  local kura_eu_flag="${5:-false}"

  cat >"${path}" <<EOF
services:
  kura-us:
    build: null
    image: ${kura_us_image}
    pull_policy: never
    environment:
      KURA_BACKFILL_ENABLED: "${kura_us_flag}"
      KURA_CAS_CAPACITY_BYTES: "1"
      KURA_PEERS: http://kura-us.kura.internal:7443,http://kura-eu.kura.internal:7443
  kura-eu:
    build: null
    image: ${kura_eu_image}
    pull_policy: never
    environment:
      KURA_BACKFILL_ENABLED: "${kura_eu_flag}"
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

assert_rollout_lacks() {
  local url="$1"
  local needle="$2"
  local body
  body="$(curl -fsS "${url}/status/rollout")"
  if [[ "${body}" == *"${needle}"* ]]; then
    echo "Expected ${url}/status/rollout to not contain ${needle}, got: ${body}" >&2
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
# per-node clauses (ready, serving, expected ring size, drained outbox, no
# critical memory pressure, and a settled catch-up family — bootstrap
# in-flight == 0 for legacy nodes, backfill_initial_cycle != pending for
# flag-on nodes, told apart by field presence exactly as gate.sh does) using
# gate.sh's own parsers. The one clause it cannot apply is cross-node
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
    local node body ready state ring_members inflight outbox pressure backfill_mode

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
        inflight="$(rollout_json_number "${body}" "bootstrap_inflight_peers")"
        backfill_mode="$(rollout_json_string "${body}" "backfill_initial_cycle")"
        outbox="$(rollout_json_number "${body}" "outbox_messages")"
        pressure="$(rollout_json_number "${body}" "memory_pressure_state")"

        [ "${ready:-false}" = "true" ] || ok=0
        [ "${state:-unknown}" = "serving" ] || ok=0
        [ "${ring_members:-0}" = "${expected_ring_members}" ] || ok=0
        if [ -n "${backfill_mode}" ]; then
          [ "${backfill_mode}" != "pending" ] || ok=0
        else
          [ "${inflight:-0}" = "0" ] || ok=0
        fi
        [ "${outbox:-0}" = "0" ] || ok=0
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

stage_0_neutral_rolling_update_and_rollback() {
  local us_url="$1"
  local eu_url="$2"

  echo "--- stage 0: previous <-> current flag-off rolling update and rollback"

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

  echo "stage 0 passed"
}

stage_1_old_to_ab_with_flag_on() {
  local us_url="$1"
  local eu_url="$2"

  echo "--- stage 1: old -> AB rolling update with KURA_BACKFILL_ENABLED on"

  dc "${PREVIOUS_OVERRIDE}" down -v --remove-orphans >/dev/null 2>&1 || true
  dc "${PREVIOUS_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair
  # The stage-1 write also seals readiness for the flag-on upgrade below: a
  # CAS artifact creates a segment, and the upgraded pod's latched readiness
  # needs ring fullness (1 of 5 segments >= the default 20%) because its
  # initial cycle cannot settle against a not-capable old peer inside the
  # harness budget.
  put_artifact "${us_url}" "skew-w1" "skew-payload-1"
  wait_for_body "$(artifact_url "${eu_url}" "skew-w1")" "skew-payload-1"
  assert_gate_green "${us_url}" "${eu_url}"

  # Upgrade kura-us only: AB image, flag on, against an old peer.
  dc "${FLAG_ON_SKEW_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair

  # The AB pod runs the backfill walker and classifies the old peer's missing
  # endpoints as the capped not-capable retry class; its initial cycle stays
  # pending until the peer upgrades (or the 30-minute wall-clock cap), which
  # is exactly why production flips the flag only after a mesh is fully >= AB.
  wait_for_rollout_contains "${us_url}" '"backfill_initial_cycle":"pending"'
  wait_for_metric_ge "${us_url}" kura_backfill_retry_backoffs_total 'class="not_capable"' 1

  # Bidirectional convergence across the skew: replication is walker-agnostic.
  put_artifact "${us_url}" "skew-w2" "skew-payload-2"
  wait_for_body "$(artifact_url "${eu_url}" "skew-w2")" "skew-payload-2"
  put_artifact "${eu_url}" "skew-w3" "skew-payload-3"
  wait_for_body "$(artifact_url "${us_url}" "skew-w3")" "skew-payload-3"

  # Old pods bootstrap from AB via the retained legacy serving: recreate the
  # old peer cold and let it catch up from the flag-on AB node.
  recreate_service_cold "${FLAG_ON_SKEW_OVERRIDE}" kura-eu kura-eu-data
  wait_for_ready_pair
  wait_for_body "$(artifact_url "${eu_url}" "skew-w1")" "skew-payload-1"
  wait_for_body "$(artifact_url "${eu_url}" "skew-w2")" "skew-payload-2"
  wait_for_body "$(artifact_url "${eu_url}" "skew-w3")" "skew-payload-3"

  # Complete the rolling update: the retrying pass succeeds once the peer is
  # capable, both cycles settle, and the fleet gate is green again.
  dc "${FLAG_ON_OVERRIDE}" up -d kura-us kura-eu >/dev/null
  wait_for_ready_pair
  wait_for_rollout_contains "${us_url}" '"backfill_initial_cycle":"complete"'
  wait_for_rollout_contains "${eu_url}" '"backfill_initial_cycle":"complete"'
  assert_gate_green "${us_url}" "${eu_url}"

  put_artifact "${eu_url}" "skew-w4" "skew-payload-4"
  wait_for_body "$(artifact_url "${us_url}" "skew-w4")" "skew-payload-4"

  echo "stage 1 passed"
}

stage_2_mixed_flag_mesh() {
  local us_url="$1"
  local eu_url="$2"

  echo "--- stage 2: mixed-flag AB mesh converges in both directions"

  dc "${MIXED_FLAG_OVERRIDE}" down -v --remove-orphans >/dev/null 2>&1 || true
  dc "${MIXED_FLAG_OVERRIDE}" up -d kura-us >/dev/null
  wait_for_http "${us_url}/ready"
  put_artifact "${us_url}" "mixed-h1" "mixed-payload-1"

  # Cold flag-off pod legacy-bootstraps from the flag-on peer (legacy serving
  # is retained until Release C).
  dc "${MIXED_FLAG_OVERRIDE}" up -d kura-eu >/dev/null
  wait_for_ready_pair
  wait_for_body "$(artifact_url "${eu_url}" "mixed-h1")" "mixed-payload-1"
  assert_rollout_lacks "${eu_url}" 'backfill_initial_cycle'

  put_artifact "${eu_url}" "mixed-h2" "mixed-payload-2"
  wait_for_body "$(artifact_url "${us_url}" "mixed-h2")" "mixed-payload-2"

  # Cold flag-on pod backfills from the flag-off peer via the unconditional
  # serving plane (index + /_internal/backfill/* exist on every AB node).
  recreate_service_cold "${MIXED_FLAG_OVERRIDE}" kura-us kura-us-data
  wait_for_ready_pair
  wait_for_body "$(artifact_url "${us_url}" "mixed-h1")" "mixed-payload-1"
  wait_for_body "$(artifact_url "${us_url}" "mixed-h2")" "mixed-payload-2"
  wait_for_rollout_contains "${us_url}" '"backfill_initial_cycle":"complete"'
  assert_gate_green "${us_url}" "${eu_url}"

  echo "stage 2 passed"
}

stage_3_ab_to_c() {
  # TODO(Release C, docs/plans/2026-07-30-001-refactor-kura-backfill-plan.md
  # Units 10 + 12): once the retirement release exists, add the AB -> C
  # rolling-update stage: build a C image, roll a flag-on AB mesh to C one
  # node at a time, and assert (a) the C node serves the flag-on AB peer via
  # the /_internal/backfill/* endpoints only, (b) legacy /_internal/bootstrap/*
  # routes are gone on C, (c) gate.sh stays green across the overlap, and
  # (d) rollback C -> AB converges. Blocked until Unit 10/12 code exists.
  echo "--- stage 3: AB -> C rolling update — SKIPPED (Release C not implemented yet)"
}

main() {
  local us_url="http://127.0.0.1:${KURA_US_PORT}"
  local eu_url="http://127.0.0.1:${KURA_EU_PORT}"

  build_image_from_ref "${PREVIOUS_REF}" "${PREVIOUS_IMAGE}" "${PREVIOUS_WORKTREE}"
  build_image_from_ref "${CURRENT_REF}" "${CURRENT_IMAGE}" "${PROJECT_ROOT}"

  write_override "${PREVIOUS_OVERRIDE}" "${PREVIOUS_IMAGE}" "${PREVIOUS_IMAGE}" false false
  write_override "${MIXED_OVERRIDE}" "${CURRENT_IMAGE}" "${PREVIOUS_IMAGE}" false false
  write_override "${FLAG_ON_SKEW_OVERRIDE}" "${CURRENT_IMAGE}" "${PREVIOUS_IMAGE}" true false
  write_override "${FLAG_ON_OVERRIDE}" "${CURRENT_IMAGE}" "${CURRENT_IMAGE}" true true
  write_override "${MIXED_FLAG_OVERRIDE}" "${CURRENT_IMAGE}" "${CURRENT_IMAGE}" true false

  stage_0_neutral_rolling_update_and_rollback "${us_url}" "${eu_url}"
  stage_1_old_to_ab_with_flag_on "${us_url}" "${eu_url}"
  stage_2_mixed_flag_mesh "${us_url}" "${eu_url}"
  stage_3_ab_to_c

  echo "Compatibility rollout passed for ${PREVIOUS_REF} -> ${CURRENT_REF} (stages 0-2; stage 3 skipped pending Release C)"
}

main
