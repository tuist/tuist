#!/bin/bash
# Joins this Tart VM to the Tailscale tailnet at boot and pins the
# pooler proxy hostname into /etc/hosts so the BEAM that runs next
# resolves it without MagicDNS.
#
# tart-cri's CNI sets up vmnet shared-NAT only; the VM has no path
# to the cluster overlay or to tailnet CGNAT addresses through the
# host. Installing tailscaled inside the VM gives each VM its own
# first-class tailnet identity — analogous to how Linux runner
# microVMs get a first-class K8s overlay identity through Kata's
# CNI integration. The Mac mini host's tailscaled stays as-is
# (advertises host metrics on :9100); the VM's tailscaled is
# independent.
#
# MagicDNS quirk: the open-source `tailscaled` variant on macOS
# (the only headless option — the App Store variant is GUI-only)
# can't reliably push DNS into `scutil`, so `--accept-dns=true`
# is a no-op for the BEAM's `gethostbyname`. We walk the netmap
# from `tailscale status --json` and write the names we need
# straight into /etc/hosts instead; the BEAM's resolver picks
# them up the same way it'd pick up MagicDNS records.
#
# Sourced from the xcresult-processor launchd plist, after
# /opt/tuist/inject-env.sh has materialized the env file but
# before `tuist start` runs.

set -euo pipefail

if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
  echo "tailscale-up: TAILSCALE_AUTH_KEY not set; refusing to start without tailnet identity" >&2
  exit 1
fi

TAILSCALE=/opt/homebrew/bin/tailscale

# Idempotency: launchd's KeepAlive restarts the wrapper every time
# the BEAM exits, and `tailscale up --reset` on each restart
# re-authenticates the device (tearing down the previous
# registration) — `tailscale ip -4` returns empty for tens of
# seconds during the reset window, and a 30s wait races and
# usually loses, putting the wrapper in a 2000+-iter crash loop.
# Only call `tailscale up` when we're not already on the tailnet.
EXISTING_IP="$(${TAILSCALE} ip -4 2>/dev/null | head -1 || true)"
if [ -n "${EXISTING_IP}" ]; then
  echo "tailscale-up: already on tailnet at ${EXISTING_IP} (launchd restart); skipping tailscale up"
  TAILNET_IP="${EXISTING_IP}"
else
  HOSTNAME_FLAG=""
  if [ -n "${TAILSCALE_HOSTNAME:-}" ]; then
    HOSTNAME_FLAG="--hostname=${TAILSCALE_HOSTNAME}"
  fi
  # --timeout is load-bearing: without it `tailscale up` blocks
  # indefinitely when tailscaled can't reach the control plane (e.g.
  # the 2026-06-26 incident, where a clobbered host VM-NAT left the
  # VM unable to complete a TCP handshake to control — SYN_SENT
  # forever). A hung `up` wedges this whole launchd chain before
  # `exec tuist start`, so the release never boots, yet the pod still
  # shows Running/Ready (tart-kubelet has no container probe). Bound
  # it instead: on timeout `up` exits non-zero, we exit 1, and
  # launchd's KeepAlive restarts the chain — so once NAT/control
  # recovers a retry succeeds and the BEAM comes up on its own,
  # rather than stranding the VM until a manual recycle.
  if ! ${TAILSCALE} up \
      --timeout=60s \
      --authkey="${TAILSCALE_AUTH_KEY}" \
      --reset \
      --ssh=true \
      --accept-dns=true \
      ${HOSTNAME_FLAG}; then
    echo "tailscale-up: tailscale up did not reach Running within timeout (control unreachable?); exiting so launchd retries" >&2
    exit 1
  fi
  TAILNET_IP=""
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    TAILNET_IP="$(${TAILSCALE} ip -4 2>/dev/null | head -1 || true)"
    if [ -n "${TAILNET_IP}" ]; then
      break
    fi
    sleep 2
  done
  if [ -z "${TAILNET_IP}" ]; then
    echo "tailscale-up: timed out waiting for tailscale ip -4 after fresh tailscale up" >&2
    exit 1
  fi
  echo "tailscale-up: joined tailnet at ${TAILNET_IP}"
fi

# Pin every peer's tailnet IPv4 + hostname into /etc/hosts so the
# BEAM's libc resolver finds the pooler proxy without MagicDNS.
# The BEGIN/END markers let us strip + rewrite on every boot — a
# peer that's been deleted from the tailnet stops appearing in
# `tailscale status` and falls out of /etc/hosts the next time
# the loop runs.
#
# Plain `tailscale status` (no --json) is one IPv4 + hostname per
# peer-line — awk picks both off without depending on jq (not in
# the macOS base image) or python's JSON parser (which also
# returns user-device display names like "Marek's MacBook" that
# embed whitespace and aren't valid /etc/hosts entries).
HOSTS_BEGIN="# BEGIN tailscale-up tailnet peers"
HOSTS_END="# END tailscale-up tailnet peers"
HOSTS_BLOCK=$(${TAILSCALE} status 2>/dev/null \
  | /usr/bin/awk '/^[0-9]/ && NF >= 2 { printf "%s\t%s\n", $1, $2 }' \
  || true)

if [ -n "${HOSTS_BLOCK}" ]; then
  sudo /usr/bin/sed -i.bak "/^${HOSTS_BEGIN}$/,/^${HOSTS_END}$/d" /etc/hosts
  sudo /bin/rm -f /etc/hosts.bak
  printf '%s\n%s\n%s\n' "${HOSTS_BEGIN}" "${HOSTS_BLOCK}" "${HOSTS_END}" | sudo /usr/bin/tee -a /etc/hosts >/dev/null
  echo "tailscale-up: wrote $(echo "${HOSTS_BLOCK}" | wc -l | tr -d ' ') tailnet peer(s) to /etc/hosts"
fi

# Diagnostic dump — captured in /var/log/xcresult-processor/stdout.log
# alongside the BEAM's own stdout. tart-kubelet doesn't proxy
# `kubectl logs` through the K8s API (the apiserver can't
# DNS-resolve Mac mini hostnames), so an operator on the tailnet
# uses `tailscale ssh admin@<vm-tailnet-ip>` and reads
# /var/log/xcresult-processor/{stdout,stderr,diagnostics}.log.
# The dump is non-fatal: if `tailscale netcheck` hangs or any
# probe errors, the BEAM still boots.
DIAG_FILE=/var/log/xcresult-processor/diagnostics.log
sudo mkdir -p "$(dirname "${DIAG_FILE}")"
sudo chown admin:staff "$(dirname "${DIAG_FILE}")"
{
  echo "==== tailscale-up: diagnostics ($(date)) ===="
  echo "-- tailscale status --"
  ${TAILSCALE} status 2>&1 || true
  echo "-- /etc/hosts (tail) --"
  /usr/bin/tail -50 /etc/hosts || true
  echo "-- DATABASE_URL host probe --"
  if [ -n "${DATABASE_URL:-}" ]; then
    HOSTPORT=$(echo "${DATABASE_URL}" | /usr/bin/sed -E 's|^[a-z]+://[^@]+@([^/]+).*|\1|')
    HOST=$(echo "${HOSTPORT}" | /usr/bin/sed -E 's|:.*||')
    PORT=$(echo "${HOSTPORT}" | /usr/bin/sed -E 's|.*:||')
    echo "URL host=${HOST} port=${PORT}"
    echo "-- /usr/bin/dscacheutil -q host -a name ${HOST} --"
    /usr/bin/dscacheutil -q host -a name "${HOST}" 2>&1 | /usr/bin/head -10 || true
    echo "-- nc -vz ${HOST} ${PORT} (10s) --"
    /usr/bin/nc -vz -w 10 "${HOST}" "${PORT}" 2>&1 || true
  else
    echo "DATABASE_URL not set"
  fi
} > "${DIAG_FILE}" 2>&1 || true
