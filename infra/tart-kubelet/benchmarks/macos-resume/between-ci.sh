#!/bin/sh
# Host hook. Place the binary, prepare-ci.sh, build-ci.sh and an operator-owned
# acquire.sh in BENCHMARK_DIR. The caller still holds the host reservation.
set -eu
: "${BENCHMARK_DIR:?set BENCHMARK_DIR to the absolute experiment directory}"
: "${KUBELET_TART_HOME:?set KUBELET_TART_HOME to the actual kubelet store}"
"$BENCHMARK_DIR/sandbox-resume-benchmark" --mode workload \
  --home "$TART_HOME" --source sandbox-base --tart "$TART_BINARY" \
  --kubelet-home "$KUBELET_TART_HOME" \
  --memory-mb 24576 --cpus 8 --timeout 8m \
  --acquire-script "$BENCHMARK_DIR/acquire.sh" \
  --prepare-script "$BENCHMARK_DIR/prepare-ci.sh" \
  --build-script "$BENCHMARK_DIR/build-ci.sh" \
  >> "$BENCHMARK_DIR/intervening-ci.jsonl" \
  2>> "$BENCHMARK_DIR/intervening-ci.log"
