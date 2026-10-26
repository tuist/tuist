#!/usr/bin/env bash
#MISE description="Check that server pods drain before they stop and the edge retries only requests that never reached a pod"
set -euo pipefail

# A server pod's preStop marks it draining (the file TuistWeb.Draining polls)
# and waits while endpoints stop routing to it. Its grace period must cover that
# wait, Bandit's shutdown_timeout and Oban's shutdown grace period (15 s each).
# The managed server Ingress moves a request to another pod only on a connect
# failure, and the controller never replays a non-idempotent request it sent.

ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
HELM="$ROOT/infra/helm"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "::error::$*" >&2
  exit 1
}

render() {
  local out="$1"
  shift
  helm template "$@" | yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/$out.json"
}

drain_file="$(sed -n 's/^  @file_path "\(.*\)"$/\1/p' "$ROOT/server/lib/tuist_web/draining.ex")"
[ -n "$drain_file" ] || fail "TuistWeb.Draining declares no @file_path"

helm dependency update "$HELM/platform" >/dev/null

for env in staging canary production; do
  render "tuist-$env" tuist "$HELM/tuist" \
    -f "$HELM/tuist/values-managed-common.yaml" \
    -f "$HELM/tuist/values-managed-$env.yaml" \
    -f "$HELM/tuist/values-ci.yaml"

  server="$(jq -c '.[] | select(.kind == "Deployment" and (.spec.template.spec.containers[0].name == "server"))' "$WORK/tuist-$env.json")"
  [ -n "$server" ] || fail "$env: no server Deployment"
  pre_stop="$(jq -r '.spec.template.spec.containers[0].lifecycle.preStop.exec.command | join(" ")' <<<"$server")"
  case "$pre_stop" in
    *"touch $drain_file;"*) ;;
    *) fail "$env: the server preStop ($pre_stop) does not create $drain_file" ;;
  esac
  wait_seconds="$(sed -n 's/.*sleep \([0-9][0-9]*\).*/\1/p' <<<"$pre_stop")"
  [ -n "$wait_seconds" ] || fail "$env: the server preStop does not wait"
  [ "$wait_seconds" -ge 15 ] || fail "$env: the server preStop waits $wait_seconds s, less than Bandit's 15 s idle timeout"
  grace="$(jq -r '.spec.template.spec.terminationGracePeriodSeconds' <<<"$server")"
  [ "$grace" -gt $((wait_seconds + 15 + 15)) ] ||
    fail "$env: terminationGracePeriodSeconds $grace does not cover the $wait_seconds s drain and 30 s of shutdown"

  annotations="$(jq -c '[.[] | select(.kind == "Ingress" and (.metadata.name | endswith("-server")))][0].metadata.annotations' "$WORK/tuist-$env.json")"
  [ "$annotations" != "null" ] || fail "$env: no server Ingress"
  for expected in \
    'nginx.ingress.kubernetes.io/proxy-next-upstream=error timeout' \
    'nginx.ingress.kubernetes.io/proxy-next-upstream-tries=3' \
    'nginx.ingress.kubernetes.io/proxy-request-buffering=off'; do
    key="${expected%%=*}"
    value="${expected#*=}"
    [ "$(jq -r --arg key "$key" '.[$key]' <<<"$annotations")" = "$value" ] ||
      fail "$env: the server Ingress must set $key to \"$value\""
  done
  if jq -r '.["nginx.ingress.kubernetes.io/proxy-next-upstream"]' <<<"$annotations" | grep -q non_idempotent; then
    fail "$env: the server Ingress must not replay non-idempotent requests"
  fi
done

for overlay in values-tuist.yaml values-tuist-canary.yaml values-tuist-staging.yaml; do
  render "platform-$overlay" platform "$HELM/platform" -f "$HELM/platform/values-hetzner.yaml" -f "$HELM/platform/$overlay"
  retry="$(jq -r '[.[] | select(.kind == "ConfigMap" and .metadata.name == "platform-ingress-nginx-controller")][0].data["retry-non-idempotent"]' "$WORK/platform-$overlay.json")"
  [ "$retry" = "false" ] || fail "$overlay: the main ingress-nginx controller must set retry-non-idempotent to \"false\", got $retry"
done

echo "Server pods drain before they stop, and the edge retries only requests that never reached a pod."
