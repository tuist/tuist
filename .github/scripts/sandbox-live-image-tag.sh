#!/usr/bin/env bash
set -euo pipefail

# Called only when the rendered chart enables sandboxd. A pre-built server
# deployment without an override for one of the DaemonSet's images (the
# `template` init container or the `sandboxd` container) must retain the live
# version, not revert it to the bootstrap pin in the chart's environment values.
namespace=$1
daemonset=$2
container=$3
image=$4
requested_tag=${5:-}
if [ -n "$requested_tag" ]; then
  tag=$requested_tag
else
  # Container names are unique across a Pod's init and regular containers.
  current_image=$(kubectl -n "$namespace" get daemonset "$daemonset" \
    -o "jsonpath={.spec.template.spec.initContainers[?(@.name==\"$container\")].image}{.spec.template.spec.containers[?(@.name==\"$container\")].image}")
  prefix="${image%:*}:"
  if [[ "$current_image" != "$prefix"* ]]; then
    echo "Cannot preserve the live $container image: missing image or unexpected repository. Supply its image tag for a first install." >&2
    exit 1
  fi
  tag=${current_image#"$prefix"}
fi
if [[ ! "$tag" =~ ^sha-[0-9a-f]{12,40}$ ]]; then
  echo "The $container image must use an immutable sha-<git-sha> tag" >&2
  exit 1
fi
printf '%s\n' "$tag"
