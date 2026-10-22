#!/usr/bin/env bash
# Read-only replacement guard. Acknowledgement never grants Kubernetes access.
set -euo pipefail
[[ $# -ge 1 && $# -le 2 ]] || { echo "usage: $0 management-tailscale|hccm [--acknowledged]" >&2; exit 2; }
component="$1"
acknowledged=false
if [[ $# -eq 2 ]]; then
  [[ "$2" == --acknowledged ]] || exit 2
  acknowledged=true
fi
root="$(cd "$(dirname "$0")/../.." && pwd)"
case "$component" in
  management-tailscale)
    namespace=mgmt-system
    name=tailscale
    desired="$(awk '/^[[:space:]]+image: / {print $2}' "$root/infra/k8s/mgmt/tailscale.yaml")"
    requirement="qualify independent management access before the singleton Recreate restart"
    ;;
  hccm)
    namespace=kube-system
    name=hcloud-cloud-controller-manager
    tag="$(awk '/^  tag: / {print $2}' "$root/infra/k8s/mgmt/bootstrap/hccm-values.yaml")"
    [[ -n "$tag" && "$tag" != *$'\n'* ]] || { echo "cannot establish desired HCCM tag" >&2; exit 1; }
    desired="docker.io/hetznercloud/hcloud-cloud-controller-manager:$tag"
    requirement="qualify Robot InternalIP load-balancer targets and independent rollback access"
    ;;
  *) echo "unknown component: $component" >&2; exit 2 ;;
esac
[[ -n "$desired" && "$desired" != *$'\n'* ]] || { echo "cannot establish one desired image" >&2; exit 1; }
raw="$(kubectl --request-timeout=30s -n "$namespace" get deployment "$name" --ignore-not-found -o json)"
if [[ -z "$raw" ]]; then
  echo "$component: initial installation; no serving deployment to replace"
  exit 0
fi
printf '%s' "$raw" | jq -e '.spec.template.spec.containers | type == "array" and length > 0 and all(.[]; (.image | type) == "string")' > /dev/null
if printf '%s' "$raw" | jq -e --arg image "$desired" '[.spec.template.spec.containers[].image] == [$image]' > /dev/null; then
  echo "$component: serving image unchanged; no replacement qualification consumed"
  exit 0
fi
if [[ "$acknowledged" != true ]]; then
  echo "Refusing unqualified $component replacement: $requirement. See infra/certificate-trust/README.md." >&2
  exit 1
fi
message="$component: explicit human qualification acknowledged for $desired"
echo "$message"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Certificate rollout qualification\n\n%s\n\nActor: %s\n\nRun: %s/%s/actions/runs/%s\n' \
    "$message" "${GITHUB_ACTOR:-unknown}" "${GITHUB_SERVER_URL:-}" \
    "${GITHUB_REPOSITORY:-}" "${GITHUB_RUN_ID:-}" >> "$GITHUB_STEP_SUMMARY"
fi
