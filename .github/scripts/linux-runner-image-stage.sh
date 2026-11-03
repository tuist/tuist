#!/usr/bin/env bash
# Stages a released Linux runner image on a cluster's hosts before
# linux-runner-image-release.yml dispatches its deploy, as runner-image-release.yml's
# announce job does for macOS. Every
# live Linux pool of the release that runs a released runner image by digest
# is retargeted to the new image and prepared through
# linux-runner-image-prepare.sh, which creates the same helpers (by target) the
# deploy's own check then finds ready, so that deploy moves the pools.
# Explicitly pinned tags are left alone; a digest-pinned explicit pool is
# staged needlessly and its helper removed by the next deploy.
# Usage: linux-runner-image-stage.sh <image@sha256> <release> <namespace>
# Waits up to LINUX_IMAGE_STAGING_WAIT_SECONDS (default 3600, as macOS) and exits non-zero
# when hosts are not ready by then; the caller warns and the deploy holds.
set -euo pipefail
image="${1:?image digest reference required}"
release="${2:?Helm release required}"
namespace="${3:?Helm namespace required}"
[[ "$image" =~ ^ghcr\.io/tuist/tuist-linux-runner@sha256:[a-f0-9]{64}$ ]] ||
  { echo "Not a Linux runner image digest: $image" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
kubectl --request-timeout=30s get runnerpools.tuist.dev --all-namespaces -o json > "$work/pools.json"
jq -c --arg image "$image" --arg release "$release" --arg namespace "$namespace" '[.items[]
  | select(.spec.os == "linux")
  | select(.metadata.annotations["meta.helm.sh/release-name"] == $release
      and .metadata.annotations["meta.helm.sh/release-namespace"] == $namespace)
  | select(.spec.image | test("^ghcr\\.io/tuist/tuist-linux-runner@sha256:[a-f0-9]{64}$"))
  | .kind = "RunnerPool" | .spec.image = $image]' "$work/pools.json" > "$work/candidates.json"
# A fleet without Ready, schedulable hosts has nothing to stage; the deploy
# moves its pools as before rather than this job waiting out its timeout.
echo '[]' > "$work/render.json"
for fleet in $(jq -r '[.[].spec.fleetSelector] | unique[]' "$work/candidates.json"); do
  kubectl --request-timeout=30s get nodes -l "kubernetes.io/os=linux,kubernetes.io/arch=amd64,node.cluster.x-k8s.io/pool=$fleet" -o json > "$work/nodes.json"
  if jq -e 'any(.items[]; .metadata.deletionTimestamp == null and .spec.unschedulable != true and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' "$work/nodes.json" >/dev/null; then
    jq --arg fleet "$fleet" --slurpfile candidates "$work/candidates.json" '. + ($candidates[0] | map(select(.spec.fleetSelector == $fleet)))' "$work/render.json" > "$work/next.json"
    mv "$work/next.json" "$work/render.json"
  else
    echo "Linux $fleet: no Ready, schedulable hosts; nothing to stage." >&2
  fi
done
if jq -e 'length == 0' "$work/render.json" >/dev/null; then
  echo "No Linux pool of $namespace/$release can stage $image." >&2
  exit 0
fi
LINUX_IMAGE_STAGING_WAIT_SECONDS="${LINUX_IMAGE_STAGING_WAIT_SECONDS:-3600}" \
  bash "$(dirname "$0")/linux-runner-image-prepare.sh" "$work/render.json" "$release" "$namespace" > /dev/null
