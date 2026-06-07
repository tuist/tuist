#!/bin/bash
# Joins this Tart VM to the Tailscale tailnet at boot, using the per-VM
# auth key the K8s Deployment injects via TAILSCALE_AUTH_KEY. Blocks
# until `tailscale ip -4` returns a tailnet IPv4 so the BEAM that runs
# next has a routable identity for the pooler proxy.
#
# tart-cri's CNI sets up vmnet shared-NAT only; the VM has no path to
# the cluster overlay or to tailnet CGNAT addresses through the host.
# Installing tailscaled inside the VM gives each VM its own first-class
# tailnet identity — analogous to how Linux runner microVMs get a
# first-class K8s overlay identity through Kata's CNI integration. The
# Mac mini host's tailscaled stays as-is (advertises host metrics on
# :9100); the VM's tailscaled is independent.
#
# Sourced from the xcresult-processor launchd plist, after
# /opt/tuist/inject-env.sh has materialized the env file but before
# `tuist start` runs.

set -euo pipefail

if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
  echo "tailscale-up: TAILSCALE_AUTH_KEY not set; refusing to start without tailnet identity" >&2
  exit 1
fi

# Hostname defaults to the K8s pod name (injected as TAILSCALE_HOSTNAME
# from the Downward API). Falls back to the VM's macOS hostname so an
# ad-hoc image boot still has a unique identity.
HOSTNAME_FLAG=""
if [ -n "${TAILSCALE_HOSTNAME:-}" ]; then
  HOSTNAME_FLAG="--hostname=${TAILSCALE_HOSTNAME}"
fi

# `--reset` so a re-claim of the same VM (Pod re-scheduled onto the same
# Mac mini host's vmnet slot) gets a fresh registration rather than
# inheriting the previous boot's state. `--accept-dns=true` is the
# default but stamp it explicitly so MagicDNS works for the pooler
# proxy hostname the BEAM dials next. `--ssh=false` because we don't
# want to expose Tailscale SSH on the VM.
if ! /opt/homebrew/bin/tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --reset \
    --ssh=false \
    --accept-dns=true \
    ${HOSTNAME_FLAG}; then
  echo "tailscale-up: tailscale up failed" >&2
  exit 1
fi

# Block until tailscaled has assigned a tailnet IPv4 — `tailscale up`
# can return 0 before MagicDNS / netmap propagate, and Postgrex's first
# dial would otherwise race the daemon's startup.
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  TAILNET_IP="$(/opt/homebrew/bin/tailscale ip -4 2>/dev/null | head -1 || true)"
  if [ -n "${TAILNET_IP}" ]; then
    echo "tailscale-up: tailnet IP ${TAILNET_IP}"
    exit 0
  fi
  sleep 2
done

echo "tailscale-up: timed out waiting for tailscale ip -4" >&2
exit 1
