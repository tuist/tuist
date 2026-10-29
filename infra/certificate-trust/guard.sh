#!/usr/bin/env bash
# Read-only replacement guard. Acknowledgement never grants Kubernetes access.
# Exit 3 means qualification is pending; read/validation errors remain failures.
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
    namespace=mgmt-tailscale
    resource=daemonset
    kind=DaemonSet
    name=tailscale
    container=tailscale
    desired="$(awk '/^[[:space:]]+image: / {print $2}' "$root/infra/k8s/mgmt/tailscale.yaml")"
    requirement="qualify independent management access, per-node identity/KubePrism and a patched rollback path before the DaemonSet rolls"
    ;;
  hccm)
    namespace=kube-system
    resource=deployment
    kind=Deployment
    name=hcloud-cloud-controller-manager
    container=hcloud-cloud-controller-manager
    tag="$(awk '/^  tag: / {print $2}' "$root/infra/k8s/mgmt/bootstrap/hccm-values.yaml")"
    [[ -n "$tag" && "$tag" != *$'\n'* ]] || { echo "cannot establish desired HCCM tag" >&2; exit 1; }
    desired="docker.io/hetznercloud/hcloud-cloud-controller-manager:$tag"
    requirement="qualify Robot InternalIP load-balancer targets and independent patched rollback access in this environment"
    ;;
  *) echo "unknown component: $component" >&2; exit 2 ;;
esac
[[ -n "$desired" && "$desired" != *$'\n'* ]] || { echo "cannot establish one desired image" >&2; exit 1; }
raw="$(kubectl --request-timeout=30s -n "$namespace" get "$resource" "$name" --ignore-not-found -o json)" || exit 1
if [[ -n "$raw" ]]; then
  printf '%s' "$raw" | jq -es --arg kind "$kind" --arg name "$name" --arg namespace "$namespace" '
    length == 1 and (.[0] |
      .kind == $kind and .metadata.name == $name and .metadata.namespace == $namespace and
      (.spec.template.spec.containers | type == "array" and length > 0 and
        all(.[]; (.name | type) == "string" and (.image | type) == "string")))' > /dev/null || exit 1
  if printf '%s' "$raw" | jq -e --arg image "$desired" --arg name "$container" \
    '[.spec.template.spec.containers[] | {name, image}] == [{name: $name, image: $image}]' > /dev/null; then
    echo "$component: serving image unchanged; no replacement qualification consumed"
    exit 0
  fi
fi
# Absence is not proof of a fresh install: the legacy Deployment may still be
# serving. Its migration is also an access replacement and needs qualification.
if [[ "$acknowledged" != true ]]; then
  echo "Refusing unqualified $component replacement or installation: $requirement. See infra/certificate-trust/management-replacements.md." >&2
  exit 3
fi
message="$component: explicit human qualification acknowledged for $desired"
echo "$message"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Certificate rollout qualification\n\n%s\n\nActor: %s\n\nRun: %s/%s/actions/runs/%s\n' \
    "$message" "${GITHUB_ACTOR:-unknown}" "${GITHUB_SERVER_URL:-}" \
    "${GITHUB_REPOSITORY:-}" "${GITHUB_RUN_ID:-}" >> "$GITHUB_STEP_SUMMARY"
fi
