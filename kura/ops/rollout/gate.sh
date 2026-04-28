#!/usr/bin/env bash

# shellcheck shell=bash

: "${ROLLOUT_TIMEOUT_SECONDS:=600}"
: "${POLL_SECONDS:=5}"
: "${ROLLOUT_STATUS_RETRY_ATTEMPTS:=3}"
: "${ROLLOUT_STATUS_RETRY_DELAY_SECONDS:=1}"

rollout_require_transport() {
  if ! declare -F node_rollout_status_get >/dev/null 2>&1; then
    echo "Define node_rollout_status_get <node> before sourcing rollout gate helpers" >&2
    return 1
  fi
}

rollout_compact_json() {
  tr -d '[:space:]'
}

rollout_json_number() {
  local body="$1"
  local key="$2"
  sed -n "s/.*\"${key}\":\\([0-9][0-9]*\\).*/\\1/p" <<<"${body}"
}

rollout_json_bool() {
  local body="$1"
  local key="$2"
  sed -n "s/.*\"${key}\":\\(true\\|false\\).*/\\1/p" <<<"${body}"
}

rollout_json_string() {
  local body="$1"
  local key="$2"
  sed -n "s/.*\"${key}\":\"\\([^\"]*\\)\".*/\\1/p" <<<"${body}"
}

rollout_collect_status_with_retry() {
  local node="$1"
  local attempts="${2:-$ROLLOUT_STATUS_RETRY_ATTEMPTS}"
  local delay_seconds="${3:-$ROLLOUT_STATUS_RETRY_DELAY_SECONDS}"
  local attempt body

  rollout_require_transport || return 1

  for attempt in $(seq 1 "${attempts}"); do
    if body="$(node_rollout_status_get "${node}" 2>/dev/null)"; then
      rollout_compact_json <<<"${body}"
      return 0
    fi
    if (( attempt < attempts )); then
      sleep "${delay_seconds}"
    fi
  done

  return 1
}

rollout_collect_cluster_load_totals() {
  local node body outbox fd_timeouts
  local total_outbox=0
  local total_fd_timeouts=0

  for node in "$@"; do
    body="$(rollout_collect_status_with_retry "${node}")" || return 1
    outbox="$(rollout_json_number "${body}" "outbox_messages")"
    fd_timeouts="$(rollout_json_number "${body}" "fd_timeout_count")"
    outbox="${outbox:-0}"
    fd_timeouts="${fd_timeouts:-0}"
    total_outbox=$((total_outbox + outbox))
    total_fd_timeouts=$((total_fd_timeouts + fd_timeouts))
  done

  printf '%s %s\n' "${total_outbox}" "${total_fd_timeouts}"
}

rollout_wait_for_gate() {
  local target_node="$1"
  local expected_ring_members="$2"
  local baseline_cluster_outbox="$3"
  local previous_cluster_fd_timeouts="$4"
  local steady_seconds="$5"
  shift 5
  local cluster_nodes=("$@")
  local threshold_outbox=$((baseline_cluster_outbox + ((baseline_cluster_outbox + 9) / 10)))
  local steady_since=""
  local deadline=$((SECONDS + ROLLOUT_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    local ok=1
    local target_seen=0
    local target_generation=""
    local observed_generation=""
    local cluster_outbox=0 cluster_fd_timeouts=0 fd_timeout_delta=0
    local node body ready state generation ring_members inflight outbox fd_timeouts pressure

    for node in "${cluster_nodes[@]}"; do
      if ! body="$(rollout_collect_status_with_retry "${node}")"; then
        ok=0
        break
      fi

      ready="$(rollout_json_bool "${body}" "ready")"
      state="$(rollout_json_string "${body}" "state")"
      generation="$(rollout_json_number "${body}" "generation")"
      ring_members="$(rollout_json_number "${body}" "ring_members")"
      inflight="$(rollout_json_number "${body}" "bootstrap_inflight_peers")"
      outbox="$(rollout_json_number "${body}" "outbox_messages")"
      fd_timeouts="$(rollout_json_number "${body}" "fd_timeout_count")"
      pressure="$(rollout_json_number "${body}" "memory_pressure_state")"

      ready="${ready:-false}"
      state="${state:-unknown}"
      generation="${generation:-0}"
      ring_members="${ring_members:-0}"
      inflight="${inflight:-0}"
      outbox="${outbox:-0}"
      fd_timeouts="${fd_timeouts:-0}"
      pressure="${pressure:-0}"

      cluster_outbox=$((cluster_outbox + outbox))
      cluster_fd_timeouts=$((cluster_fd_timeouts + fd_timeouts))

      if [[ "${node}" == "${target_node}" ]]; then
        target_seen=1
        target_generation="${generation}"
      fi

      if [[ -z "${observed_generation}" ]]; then
        observed_generation="${generation}"
      elif [[ "${generation}" != "${observed_generation}" ]]; then
        ok=0
      fi

      if [[ "${ready}" != "true" ]]; then
        ok=0
      fi
      if [[ "${state}" != "serving" ]]; then
        ok=0
      fi
      if [[ "${ring_members}" != "${expected_ring_members}" ]]; then
        ok=0
      fi
      if (( inflight != 0 )); then
        ok=0
      fi
      if (( pressure == 2 )); then
        ok=0
      fi
    done

    if (( cluster_fd_timeouts >= previous_cluster_fd_timeouts )); then
      fd_timeout_delta=$((cluster_fd_timeouts - previous_cluster_fd_timeouts))
    else
      fd_timeout_delta=0
    fi
    previous_cluster_fd_timeouts="${cluster_fd_timeouts}"

    if [[ "${target_seen}" != "1" ]]; then
      ok=0
    fi
    if [[ -n "${observed_generation}" && -n "${target_generation}" && "${target_generation}" != "${observed_generation}" ]]; then
      ok=0
    fi
    if (( cluster_outbox > threshold_outbox )); then
      ok=0
    fi
    if (( fd_timeout_delta > 0 )); then
      ok=0
    fi

    if [[ "${ok}" == "1" ]]; then
      if [[ -z "${steady_since}" ]]; then
        steady_since="${SECONDS}"
      elif (( SECONDS - steady_since >= steady_seconds )); then
        return 0
      fi
    else
      steady_since=""
    fi

    sleep "${POLL_SECONDS}"
  done

  echo "Timed out waiting for rollout gate on ${target_node}" >&2
  return 1
}
