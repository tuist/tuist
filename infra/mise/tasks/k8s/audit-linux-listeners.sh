#!/usr/bin/env bash
#MISE description="Read-only TCP/MPTCP listener snapshot on a Linux host (run as root on the host)"
# Additional arguments are paths to network namespaces pinned outside the standard directories.
# Exit 0: no MPTCP listeners observed; 1: observed MPTCP; 2: incomplete audit.
set -euo pipefail

if [[ $(uname -s) != Linux || $EUID -ne 0 ]]; then
  echo "Run as root on the Linux host, with its full /proc and mount namespace visible." >&2
  exit 2
fi
for command in nsenter ss stat cat mktemp; do
  if ! command -v "$command" >/dev/null; then
    echo "Missing required command: $command" >&2
    exit 2
  fi
done

umask 077
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
shopt -s nullglob
declare -A seen=()
incomplete=0
found=0
count=0

printf 'Host: %s\nBooted kernel: %s\nUTC: %s\n' "$(uname -n)" "$(uname -r)" "$(date -u +%FT%TZ)"
echo "Snapshot only; no patch or exploitability verdict. Namespace paths/process details are internal."

# Include process namespaces AND pinned namespaces with no resident process.
# Host-network pods share the host namespace and are intentionally deduplicated.
for namespace in /proc/1/ns/net /proc/[0-9]*/ns/net /run/netns/* /run/docker/netns/* "$@"; do
  if ! inode=$(stat -Lc '%i' "$namespace" 2>"$scratch/error"); then
    echo "INCOMPLETE: cannot inspect $namespace (possibly exited); rerun." >&2
    cat "$scratch/error" >&2
    incomplete=1
    continue
  fi
  if [[ -v seen[$inode] ]]; then
    continue
  fi
  seen[$inode]=1
  count=$((count + 1))
  printf '\nNamespace: %s (%s)\n' "$inode" "$namespace"

  printf 'net.mptcp.enabled: '
  if ! nsenter --net="$namespace" cat /proc/sys/net/mptcp/enabled 2>"$scratch/error"; then
    echo "INCOMPLETE: cannot read net.mptcp.enabled" >&2
    cat "$scratch/error" >&2
    incomplete=1
  fi

  echo "TCP listeners (including IPv4 and IPv6):"
  if ! nsenter --net="$namespace" ss -H -l -n -t -p >"$scratch/tcp" 2>"$scratch/error" || [[ -s $scratch/error ]]; then
    echo "INCOMPLETE: TCP diagnostics failed" >&2
    cat "$scratch/error" >&2
    incomplete=1
  fi
  cat "$scratch/tcp"

  echo "MPTCP listeners (checked even when net.mptcp.enabled=0):"
  if ! nsenter --net="$namespace" ss -H -l -n -M -p >"$scratch/mptcp" 2>"$scratch/error" || [[ -s $scratch/error ]]; then
    echo "INCOMPLETE: MPTCP diagnostics failed; empty output is not a negative result" >&2
    cat "$scratch/error" >&2
    incomplete=1
  elif [[ -s $scratch/mptcp ]]; then
    found=1
    echo "MPTCP_LISTENER_OBSERVED"
  fi
  cat "$scratch/mptcp"
done

printf '\nNamespaces inspected: %s\n' "$count"
if ((incomplete)); then
  echo "INCOMPLETE: do not infer absence of MPTCP or patch coverage." >&2
  exit 2
elif ((found)); then
  echo "MPTCP listeners observed; assess reachability before claiming exposure."
  exit 1
fi
echo "No MPTCP listeners observed in this snapshot; the TCP CVE still requires kernel remediation."
