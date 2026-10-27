#!/usr/bin/env bash
set -euo pipefail

# Called only when the rendered chart enables sandboxd. A pre-built server
# deployment without a template override must retain the live guest version,
# not revert it to the bootstrap pin in the chart's environment values.
namespace=$1
daemonset=$2
template_image=$3
requested_tag=${4:-}
if [ -n "$requested_tag" ]; then
  tag=$requested_tag
else
  current_image=$(kubectl -n "$namespace" get daemonset "$daemonset" \
    -o 'jsonpath={.spec.template.spec.initContainers[?(@.name=="template")].image}')
  prefix="${template_image%:*}:"
  if [[ "$current_image" != "$prefix"* ]]; then
    echo "Cannot preserve sandbox template: missing image or unexpected repository. Supply sandbox_template_image_tag for a first install." >&2
    exit 1
  fi
  tag=${current_image#"$prefix"}
fi
if [[ ! "$tag" =~ ^sha-[0-9a-f]{12,40}$ ]]; then
  echo "Sandbox template must use an immutable sha-<git-sha> tag" >&2
  exit 1
fi
printf '%s\n' "$tag"
