#!/usr/bin/env bash
set -euo pipefail

chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checks=0

render() {
  local args=(template envelope-validation "$chart"
    -f "$chart/values-self-hosted-ci.yaml"
    -f "$chart/values-ci.yaml"
    --set server.cluster.enabled=true)
  local override
  for override in "$@"; do
    args+=(--set "$override")
  done
  helm "${args[@]}"
}

check_envelope() {
  local label="$1" expected="$2" actual
  shift 2
  # Filter in memory: rendered Secrets must never reach files or test output.
  if ! actual="$(render "$@" 2>/dev/null | awk '
    /^---$/ { deployment = 0 }
    /^# Source: tuist\/templates\/server-deployment.yaml$/ { deployment = 1 }
    deployment && /- name: TUIST_RATE_LIMIT_FALLBACK_REPLICAS$/ {
      if (getline <= 0 || $0 !~ /^[[:space:]]+value: "[0-9]+"$/) exit 1
      gsub(/[^0-9]/, "")
      print
      found++
    }
    END { if (found != 1) exit 1 }
  ')"; then
    printf 'FAIL: %s (rendering failed or envelope missing; output suppressed)\n' "$label" >&2
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
  checks=$((checks + 1))
  printf 'PASS: %s\n' "$label"
}

check_rejected() {
  local label="$1" key="$2" error
  shift 2
  if error="$(render "$@" 2>&1 >/dev/null)"; then
    printf 'FAIL: %s (invalid configuration rendered)\n' "$label" >&2
    exit 1
  fi
  if ! grep -Fq -- "$key" <<< "$error"; then
    printf 'FAIL: %s (expected validation error missing; output suppressed)\n' "$label" >&2
    exit 1
  fi
  checks=$((checks + 1))
  printf 'PASS: %s\n' "$label"
}

check_envelope 'default floor' 5
check_envelope 'fixed replicas include terminating generation and surge' 9 server.replicaCount=4
check_envelope 'HPA maximum, not current replicas' 11 server.autoscaling.enabled=true server.autoscaling.maxReplicas=5
check_envelope 'percentage surge rounds up' 7 server.replicaCount=3 server.strategy.rollingUpdate.maxSurge=33%
for key in server.strategy server.strategy.rollingUpdate server.strategy.rollingUpdate.maxSurge; do
  check_envelope "Kubernetes default for null $key" 12 server.replicaCount=5 "$key=null"
done
check_envelope 'partial override keeps chart surge default' 11 server.replicaCount=5 server.strategy.rollingUpdate.maxUnavailable=0
check_envelope 'explicit zero surge is not defaulted' 10 server.replicaCount=5 server.strategy.rollingUpdate.maxSurge=0
check_envelope 'Recreate has no surge' 10 server.replicaCount=5 server.strategy.type=Recreate server.strategy.rollingUpdate=null
for value in -1 invalid 1.5%; do
  check_rejected "invalid surge $value" server.strategy.rollingUpdate.maxSurge "server.strategy.rollingUpdate.maxSurge=$value"
done
check_envelope 'larger explicit allowance' 20 server.rateLimitFallbackReplicas=20
for value in -1 invalid 4 5; do
  check_rejected "invalid or insufficient allowance $value" server.rateLimitFallbackReplicas server.replicaCount=4 "server.rateLimitFallbackReplicas=$value"
done
printf 'All %s rollout-envelope checks passed\n' "$checks"
