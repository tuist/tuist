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
# proxy hostname the BEAM dials next. `--ssh=true` exposes Tailscale
# SSH (ACL-gated, op-only) so operators can shell into a VM via
# tailnet without ever touching the host or the tart CLI — diagnostic
# parity with what every other tailnet device offers.
if ! /opt/homebrew/bin/tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --reset \
    --ssh=true \
    --accept-dns=true \
    ${HOSTNAME_FLAG}; then
  echo "tailscale-up: tailscale up failed" >&2
  exit 1
fi

# Block until tailscaled has assigned a tailnet IPv4 — `tailscale up`
# can return 0 before MagicDNS / netmap propagate, and Postgrex's first
# dial would otherwise race the daemon's startup.
TAILNET_IP=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  TAILNET_IP="$(/opt/homebrew/bin/tailscale ip -4 2>/dev/null | head -1 || true)"
  if [ -n "${TAILNET_IP}" ]; then
    echo "tailscale-up: tailnet IP ${TAILNET_IP}"
    break
  fi
  sleep 2
done

if [ -z "${TAILNET_IP}" ]; then
  echo "tailscale-up: timed out waiting for tailscale ip -4" >&2
  exit 1
fi

# Diagnostic dump — captured in /var/log/xcresult-processor/stdout.log
# alongside the BEAM's own stdout. tart-kubelet doesn't proxy `kubectl
# logs` through the K8s API (the apiserver can't DNS-resolve Mac mini
# hostnames), and the Tailscale SSH ACL doesn't yet permit
# subnet-router→VM SSH, so we publish the diag dump over plain HTTP
# at <vm-tailnet-ip>:8000/diagnostics.log instead. Anyone on the
# tailnet can `wget` it; the wide-open `grants` rule covers the
# port. Removable once kubectl logs / Tailscale SSH is wired.
DIAG_FILE=/var/log/xcresult-processor/diagnostics.log
sudo mkdir -p "$(dirname "${DIAG_FILE}")"
sudo chown admin:staff "$(dirname "${DIAG_FILE}")"
{
  echo "==== tailscale-up: diagnostics ($(date)) ===="
  echo "-- tailscale status --"
  /opt/homebrew/bin/tailscale status || true
  echo "-- tailscale netcheck --"
  /opt/homebrew/bin/tailscale netcheck 2>/dev/null | head -30 || true
  echo "-- ifconfig (utun + en* + lo) --"
  /sbin/ifconfig | awk '/^utun|^en|^lo/ { keep=1 } /^[a-z]/ { if (!/^utun|^en|^lo/) keep=0 } keep' || true
  echo "-- netstat -rn --"
  /usr/sbin/netstat -rn || true
  echo "-- scutil DNS state --"
  /usr/sbin/scutil --dns 2>/dev/null | head -60 || true
  echo "-- pf state --"
  echo 'admin' | sudo -S /sbin/pfctl -s rules 2>&1 | head -20 || true
  echo "-- DATABASE_URL host probe --"
  if [ -n "${DATABASE_URL:-}" ]; then
    # Parse host:port from the URL (postgres://user:pass@host:port/db).
    HOSTPORT=$(echo "${DATABASE_URL}" | sed -E 's|^[a-z]+://[^@]+@([^/]+).*|\1|')
    HOST=$(echo "${HOSTPORT}" | sed -E 's|:.*||')
    PORT=$(echo "${HOSTPORT}" | sed -E 's|.*:||')
    echo "URL host=${HOST} port=${PORT}"
    echo "-- nslookup ${HOST} --"
    /usr/bin/nslookup "${HOST}" 2>&1 | head -10 || true
    echo "-- nc -vz ${HOST} ${PORT} (10s) --"
    /usr/bin/nc -vz -w 10 "${HOST}" "${PORT}" 2>&1 || true
    echo "-- route get ${HOST} --"
    /sbin/route -n get "${HOST}" 2>&1 | head -15 || true
  else
    echo "DATABASE_URL not set"
  fi
} 2>&1 | sudo tee "${DIAG_FILE}" >/dev/null || true

# Start a tiny HTTP file server in the log directory so an operator
# on the tailnet can `wget http://<vm-tailnet-ip>:8000/diagnostics.log`
# or `…/stdout.log` to read the BEAM's boot output. Forks into the
# background; failures are non-fatal. macOS ships python3 (Command
# Line Tools), no extra deps. Bound to 0.0.0.0 because the VM's
# tailscale0 carries the only routable interface for tailnet clients.
nohup /usr/bin/python3 -m http.server --bind 0.0.0.0 --directory /var/log/xcresult-processor 8000 >/dev/null 2>&1 &
disown 2>/dev/null || true

echo "tailscale-up: timed out waiting for tailscale ip -4" >&2
exit 1

