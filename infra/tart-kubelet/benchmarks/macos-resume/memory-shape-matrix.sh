#!/bin/bash
# The caller owns an exclusive staging reservation for the entire invocation.
# Run from a staged copy of this directory; pass an instrumented Tart binary.
set -euo pipefail
root=${1:?usage: memory-shape-matrix.sh /absolute/experiment-root /absolute/tart}
tart_binary=${2:?provide the profiling Tart binary}
: "${KUBELET_TART_HOME:?set KUBELET_TART_HOME to the actual kubelet store}"
case "$root:$tart_binary" in /*:/*) ;; *) exit 1 ;; esac
scripts=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$root/results"
printf '/usr/bin/true\n' > "$root/idle-build.sh"
# Stabilize the fresh-boot baseline without starting simulator or build tools.
printf 'sleep 30\n' > "$root/idle-prepare.sh"
export TUIST_TART_PROFILE=1
for workload in idle fixture; do
  for memory in 8192 16384 24576; do
    output="$root/results/$workload-$memory"
    test ! -e "$output.jsonl"
    prepare="$root/idle-prepare.sh"
    build="$root/idle-build.sh"
    if [ "$workload" = fixture ]; then
      prepare="$root/fixture-prepare.sh"
      build="$scripts/build-fixture.sh"
    fi
    "$root/benchmark" --home "$root/store" --source sandbox-base \
      --kubelet-home "$KUBELET_TART_HOME" \
      --tart "$tart_binary" --memory-mb "$memory" --cpus 8 --cycles 3 \
      --timeout 15m --acquire-script "$root/acquire.sh" \
      --prepare-script "$prepare" --build-script "$build" \
      --before-suspend-script "$scripts/guest-memory-profile.sh" \
      --gate-command-probe > "$output.jsonl" 2> "$output.log"
  done
done
