#!/usr/bin/env bash
set -euo pipefail

# Waits until a remote execution worker's daemon has both prebuilt VM shapes
# (PREBUILD_SHAPES) of the template tag ready: built now (`template ready`)
# or already on the host from an earlier run (`default template` at startup
# lists them in ready_shapes). Fails on a template build failure, so a broken
# image fails the deploy instead of the account's actions.
#
# Usage: remote-execution-worker-templates.sh <namespace> <pod> <template tag>
namespace=$1
pod=$2
tag=$3
for _ in $(seq 1 120); do
  log=$(kubectl -n "$namespace" logs "$pod" -c sandboxd 2>/dev/null || true)
  failed=$(jq -Rr --arg tag "$tag" \
    'fromjson? | select(.tag == $tag and .msg == "template build failed") | "\(.shape): \(.error)"' <<< "$log")
  if [ -n "$failed" ]; then
    echo "::error::$pod failed to build template $tag: $failed"
    exit 1
  fi
  ready=$(jq -Rr --arg tag "$tag" '
    fromjson? | select(.tag == $tag)
    | if .msg == "template ready" then 1
      elif .msg == "default template" then (.ready_shapes | length)
      else empty end' <<< "$log" | awk '{n += $1} END {print n + 0}')
  if [ "$ready" -ge 2 ]; then
    echo "$pod has its templates ready"
    exit 0
  fi
  sleep 5
done
echo "::error::$pod did not report its templates ready within ten minutes"
kubectl -n "$namespace" logs "$pod" -c sandboxd --tail=80 || true
exit 1
