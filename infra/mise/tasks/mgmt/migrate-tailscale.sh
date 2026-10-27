#!/usr/bin/env bash
#MISE description="Move the management cluster's tailscaled from the single-node Deployment in mgmt-system to the per-node DaemonSet in mgmt-tailscale, keeping the existing node's tailnet identity. A no-op once done."

# Needs KUBECONFIG for the management cluster. Run before
# `kubectl apply -f infra/k8s/mgmt/tailscale.yaml`.
#
# The Deployment kept its state in mgmt-system/tailscale-state, under the
# hostname tuist-mgmt, which is also the node's name. The DaemonSet keeps
# each node's state in mgmt-tailscale/tailscale-state-<node name>. Copying
# the state to the name for the node the Deployment ran on, before the
# DaemonSet starts, lets that node reconnect as the same device: same
# tailnet IP and MagicDNS name. The OAuth Secret is copied too.
#
# The Deployment is deleted first and its Pod waited for, so the state is no
# longer changing when it is copied and two tailscaled never share it. The
# mgmt-system Secrets are left in place: re-applying the old manifest from
# git restores the previous setup.

set -euo pipefail

LEGACY_NAMESPACE="mgmt-system"
NAMESPACE="mgmt-tailscale"

if ! kubectl -n "$LEGACY_NAMESPACE" get deployment tailscale >/dev/null 2>&1; then
  echo "no tailscale Deployment in $LEGACY_NAMESPACE; nothing to migrate"
  exit 0
fi

# Copies a Secret's type and data under a new name. `kubectl create`, not
# `apply`, so the data does not land in the last-applied annotation.
copy_secret() {
  local from="$1" to="$2"
  if kubectl -n "$NAMESPACE" get secret "$to" >/dev/null 2>&1; then
    echo "$NAMESPACE/$to already exists"
    return
  fi
  kubectl -n "$LEGACY_NAMESPACE" get secret "$from" -o json |
    jq --arg name "$to" --arg namespace "$NAMESPACE" \
      '{apiVersion, kind, type, data, metadata: {name: $name, namespace: $namespace}}' |
    kubectl create -f - >/dev/null
  echo "copied $LEGACY_NAMESPACE/$from to $NAMESPACE/$to"
}

node="$(kubectl -n "$LEGACY_NAMESPACE" get pods -l app=tailscale -o jsonpath='{.items[0].spec.nodeName}')"
[[ -n "$node" ]] || { echo "error: no tailscale Pod in $LEGACY_NAMESPACE to take the node name from" >&2; exit 1; }

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
copy_secret tailscale-oauth tailscale-oauth

kubectl -n "$LEGACY_NAMESPACE" delete deployment tailscale --wait=true
kubectl -n "$LEGACY_NAMESPACE" wait --for=delete pod -l app=tailscale --timeout=3m
copy_secret tailscale-state "tailscale-state-$node"

kubectl -n "$LEGACY_NAMESPACE" delete rolebinding tailscale --ignore-not-found
kubectl -n "$LEGACY_NAMESPACE" delete role tailscale --ignore-not-found
kubectl -n "$LEGACY_NAMESPACE" delete serviceaccount tailscale --ignore-not-found
