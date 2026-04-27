#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <release> <namespace> [helm upgrade args...]" >&2
  exit 1
fi

RELEASE_NAME="$1"
NAMESPACE="$2"
shift 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$SCRIPT_DIR}"
STATEFULSET_NAME="${STATEFULSET_NAME:-$RELEASE_NAME}"
CONTAINER_NAME="${CONTAINER_NAME:-kura}"
KURA_HTTP_PORT="${KURA_HTTP_PORT:-4000}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
ROLLOUT_TIMEOUT_SECONDS="${ROLLOUT_TIMEOUT_SECONDS:-600}"
READY_STEADY_STATE_SECONDS="${READY_STEADY_STATE_SECONDS:-120}"
CANARY_STEADY_STATE_SECONDS="${CANARY_STEADY_STATE_SECONDS:-600}"
POLL_SECONDS="${POLL_SECONDS:-5}"
ROLLOUT_NONCE="${ROLLOUT_NONCE:-$(date +%s)}"
HELM_ARGS=("$@")

source "${SCRIPT_DIR}/../../rollout/gate.sh"

require_non_empty() {
  local value="$1"
  local message="$2"
  if [[ -z "${value}" ]]; then
    echo "${message}" >&2
    exit 1
  fi
}

pod_name_for_ordinal() {
  local ordinal="$1"
  printf '%s-%s' "${STATEFULSET_NAME}" "${ordinal}"
}

node_rollout_status_get() {
  local node="$1"
  kubectl exec -n "${NAMESPACE}" "${node}" -c "${CONTAINER_NAME}" -- \
    curl -fsS "http://127.0.0.1:${KURA_HTTP_PORT}/status/rollout"
}

helm_upgrade_partition() {
  local partition="$1"
  helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --wait \
    --timeout "${HELM_TIMEOUT}" \
    --set "updateStrategy.rollingUpdatePartition=${partition}" \
    --set-string "podAnnotations.rolloutNonce=${ROLLOUT_NONCE}" \
    "${HELM_ARGS[@]}"
}

wait_for_updated_revision() {
  local pod_name="$1"
  local target_revision="$2"
  local deadline=$((SECONDS + ROLLOUT_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    local revision
    revision="$(kubectl get pod "${pod_name}" -n "${NAMESPACE}" -o jsonpath='{.metadata.labels.controller-revision-hash}' 2>/dev/null || true)"
    if [[ "${revision}" == "${target_revision}" ]]; then
      return 0
    fi
    sleep "${POLL_SECONDS}"
  done

  echo "Timed out waiting for ${pod_name} to reach revision ${target_revision}" >&2
  return 1
}

main() {
  local replicas target_revision ordinal pod_name baseline_cluster_outbox baseline_cluster_fd_timeouts current_cluster_fd_timeouts
  local cluster_nodes=()

  replicas="$(kubectl get statefulset "${STATEFULSET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
  require_non_empty "${replicas}" "Failed to resolve replica count for ${STATEFULSET_NAME}"

  for ((ordinal = 0; ordinal < replicas; ordinal += 1)); do
    cluster_nodes+=("$(pod_name_for_ordinal "${ordinal}")")
  done

  helm_upgrade_partition "${replicas}"
  target_revision="$(kubectl get statefulset "${STATEFULSET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.updateRevision}')"
  require_non_empty "${target_revision}" "Failed to resolve target controller revision for ${STATEFULSET_NAME}"

  for ((ordinal = replicas - 1; ordinal >= 0; ordinal -= 1)); do
    pod_name="$(pod_name_for_ordinal "${ordinal}")"
    read -r baseline_cluster_outbox baseline_cluster_fd_timeouts < <(
      rollout_collect_cluster_load_totals "${cluster_nodes[@]}"
    )

    helm_upgrade_partition "${ordinal}"
    wait_for_updated_revision "${pod_name}" "${target_revision}"
    rollout_wait_for_gate \
      "${pod_name}" \
      "${replicas}" \
      "${baseline_cluster_outbox}" \
      "${baseline_cluster_fd_timeouts}" \
      "${READY_STEADY_STATE_SECONDS}" \
      "${cluster_nodes[@]}"

    if (( ordinal == replicas - 1 )); then
      read -r _ current_cluster_fd_timeouts < <(
        rollout_collect_cluster_load_totals "${cluster_nodes[@]}"
      )
      rollout_wait_for_gate \
        "${pod_name}" \
        "${replicas}" \
        "${baseline_cluster_outbox}" \
        "${current_cluster_fd_timeouts}" \
        "${CANARY_STEADY_STATE_SECONDS}" \
        "${cluster_nodes[@]}"
    fi
  done

  echo "Warm rollout completed for ${STATEFULSET_NAME} in namespace ${NAMESPACE}"
}

main
