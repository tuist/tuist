#!/bin/sh
# Installs the per-pod egress ceiling as a root qdisc on the pod's eth0,
# inside the pod network namespace. Runs as an init container with
# NET_ADMIN; the qdisc lives and dies with the pod netns, so there is no
# cleanup path and no steady-state process.
#
# Fail-closed by design: any failure here must fail the init container so
# the pod never starts unshaped. Do not add fallbacks or ignore exit codes.
set -eu

case "${EGRESS_BURST_MBPS:-}" in
  '' | *[!0-9]*)
    echo "EGRESS_BURST_MBPS must be a positive integer number of Mbit/s, got: '${EGRESS_BURST_MBPS:-}'" >&2
    exit 1
    ;;
esac
if [ "${EGRESS_BURST_MBPS}" -le 0 ]; then
  echo "EGRESS_BURST_MBPS must be greater than zero, got: '${EGRESS_BURST_MBPS}'" >&2
  exit 1
fi

RATE="${EGRESS_BURST_MBPS}mbit"

# htb root with a single default class rather than bare tbf: identical
# behavior today, but leaves room for a small high-priority class (probe
# traffic) later without changing the mechanism. fq_codel as the leaf keeps
# the queue fair and short under saturation; quantum 60000 avoids htb's
# quantum warnings at >=1 Gbit rates. `replace` keeps restarts idempotent.
tc qdisc replace dev eth0 root handle 1: htb default 10
tc class replace dev eth0 parent 1: classid 1:10 htb \
  rate "$RATE" ceil "$RATE" burst 1m cburst 1m quantum 60000
tc qdisc replace dev eth0 parent 1:10 handle 10: fq_codel

# Log the final state so `kubectl logs <pod> -c egress-qdisc` shows what got
# installed.
tc -s qdisc show dev eth0
tc -s class show dev eth0
