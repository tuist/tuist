#!/usr/bin/env bash
# Run on each authorized Linux host, reversing source/destination for the second
# run. The workload must wait for an authenticated replica read of newly written
# data. Captures prove the underlay; a successful private-address ping does not.
set -euo pipefail

if [[ $# -lt 6 || $5 != -- ]]; then
  echo "usage: $0 PRIVATE_INTERFACE PUBLIC_INTERFACE PEER_UNDERLAY_IP PEER_PUBLIC_IP -- WORKLOAD_COMMAND [ARG...]" >&2
  exit 2
fi
private_if=$1
public_if=$2
peer_ip=$3
peer_public_ip=$4
shift 5
[[ $private_if != "$public_if" ]] || { echo 'interfaces must differ' >&2; exit 2; }
[[ $peer_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'peer must be an IPv4 address' >&2; exit 2; }
[[ $peer_public_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'public peer must be an IPv4 address' >&2; exit 2; }
for interface in "$private_if" "$public_if"; do
  [[ $interface =~ ^[a-zA-Z0-9_.:-]+$ && -d /sys/class/net/$interface ]] || { echo "unknown interface: $interface" >&2; exit 2; }
done
for tool in ip jq tcpdump timeout; do command -v "$tool" >/dev/null; done
[[ $(id -u) == 0 ]] || { echo 'capture requires root on the authorized host' >&2; exit 2; }

evidence=$(mktemp -d /tmp/kura-private-path.XXXXXXXX)
echo "Evidence: $evidence"
ip -j route get "$peer_ip" | tee "$evidence/route.json" | jq -e --arg dev "$private_if" 'length == 1 and .[0].dev == $dev' >/dev/null
ip -j address show dev "$private_if" > "$evidence/private-addresses.json"
ip -s -j link show dev "$private_if" > "$evidence/private-before.json"
ip -s -j link show dev "$public_if" > "$evidence/public-before.json"

pids=()
stop_captures() {
  for pid in "${pids[@]}"; do kill -INT "$pid" 2>/dev/null || true; done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
  pids=()
}
trap stop_captures EXIT
# Include the public address too: a fallback can change the destination as well
# as the interface. Do not filter by port and miss an HTTPS gateway or overlay.
# The fixed snaplen limits capture to the initial packet headers.
filter="host $peer_ip or host $peer_public_ip"
for interface in "$private_if" "$public_if"; do
  tcpdump -n -U -i "$interface" -s 64 -w "$evidence/$interface.pcap" "$filter" 2> "$evidence/$interface.log" &
  pids+=("$!")
  ready=false
  for _ in {1..50}; do
    if grep -q 'listening on' "$evidence/$interface.log"; then ready=true; break; fi
    kill -0 "$!" 2>/dev/null || { cat "$evidence/$interface.log" >&2; exit 1; }
    sleep 0.1
  done
  "$ready" || { echo "capture did not start: $interface" >&2; exit 1; }
done
result=0
timeout --signal=TERM --kill-after=5 60 "$@" > "$evidence/workload.log" 2>&1 || result=$?
stop_captures
ip -s -j link show dev "$private_if" > "$evidence/private-after.json"
ip -s -j link show dev "$public_if" > "$evidence/public-after.json"
private_sent=$(tcpdump -nn -r "$evidence/$private_if.pcap" "dst host $peer_ip" 2>/dev/null | wc -l)
private_received=$(tcpdump -nn -r "$evidence/$private_if.pcap" "src host $peer_ip" 2>/dev/null | wc -l)
public_packets=$(tcpdump -nn -r "$evidence/$public_if.pcap" 2>/dev/null | wc -l)
printf 'workload_exit=%d private_sent=%d private_received=%d public_packets=%d\n' "$result" "$private_sent" "$private_received" "$public_packets" | tee "$evidence/result.txt"
[[ $result == 0 && $private_sent -gt 0 && $private_received -gt 0 && $public_packets == 0 ]]
