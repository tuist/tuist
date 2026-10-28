#!/bin/sh
# Diagnostic only: RAM_SNAPSHOT_DIR must be a separately mounted disposable
# RAM disk. Allocate and verify that mount before reserving the experiment.
set -eu
: "${TART_HOME:?}" "${SANDBOX_VM:?}" "${RAM_SNAPSHOT_DIR:?}"
case "$SANDBOX_VM" in sbx-bench-*) ;; *) exit 1 ;; esac
case "$SANDBOX_VM" in */*) exit 1 ;; esac
test -d "$RAM_SNAPSHOT_DIR"
state="$TART_HOME/vms/$SANDBOX_VM/state.vzvmsave"
copy="$RAM_SNAPSHOT_DIR/$SANDBOX_VM.vzvmsave"
test -f "$state"
test ! -L "$state"
# Retain the original until copying succeeds. This cost is between_ms, outside
# wakeup: a retained RAM snapshot still consumes CI headroom during the pause.
cp "$state" "$copy"
ln -s "$copy" "$state.ram-link"
mv -f "$state.ram-link" "$state"
