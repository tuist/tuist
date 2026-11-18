#!/usr/bin/env bash
# Resolve independently of the server/controller revision. An API outage must
# never look like an absent driver. Existing tag pins are preserved verbatim;
# every explicit upgrade requires a verified immutable digest.
set -euo pipefail
repository=ghcr.io/tuist/kura-volumes-csi
requested="${KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT:-}"
namespace="$(kubectl get namespace kura-volumes --ignore-not-found -o name)"
current=""
if [ -n "$namespace" ]; then
  current="$(kubectl -n kura-volumes get daemonsets -l app.kubernetes.io/component=kura-volumes-csi -o json |
    jq -er '[.items[].spec.template.spec.containers[] | select(.name == "driver") | .image] | unique |
      if length == 0 then "" elif length == 1 then .[0] else error("CSI releases disagree; reconcile explicitly") end')"
fi
tag=""
digest=""
if [ -n "$requested" ]; then
  [[ "$requested" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid CSI image digest' >&2; exit 1; }
  docker manifest inspect "${repository}@${requested}" >/dev/null
  digest="$requested"
elif [[ "$current" == "${repository}@sha256:"* ]]; then
  digest="${current#"${repository}@"}"
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 1
elif [[ "$current" == "${repository}:"* ]]; then
  tag="${current#"${repository}:"}"
  [[ "$tag" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]] || exit 1
elif [ -n "$current" ]; then
  echo 'Unexpected installed CSI image; refusing to disable or replace it' >&2
  exit 1
fi
{
  echo "KURA_VOLUMES_CSI_IMAGE_TAG=$tag"
  echo "KURA_VOLUMES_CSI_IMAGE_DIGEST=$digest"
} >> "${GITHUB_ENV:?}"
echo "Kura CSI: ${digest:-${tag:-absent; installation remains disabled}}"
