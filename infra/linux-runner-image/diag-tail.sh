#!/usr/bin/env bash
# Stream actions/runner diagnostic logs to stdout so they reach Loki via
# the pod-log pipeline.
#
# The runner writes per-process diagnostic output (Listener handshake,
# session lifecycle, Worker job execution, network/retry errors, HTTP
# 5xx responses from the Actions service) to:
#
#   $RUNNER_HOME/_diag/Runner_*.log
#   $RUNNER_HOME/_diag/Worker_*.log
#
# Those files live inside the container filesystem and die with the
# Pod, so whenever a runner exits abnormally (silent microVM teardown,
# or — as seen on the post-#11114 "lost communication" run — a clean
# exit 0 while GitHub stops seeing the heartbeat) nothing survives in
# Loki to explain it.
#
# `ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1` is advertised in community
# threads as the way to mirror this output to stdout (originally added
# for actions-runner-controller), but verified empirically here that
# active-job pods land in Loki with no stdout at all — the env var
# does not surface _diag in our shape. Reading the files and copying
# lines to stdout is the only mechanism that reliably reaches alloy.
#
# Each emitted line is prefixed with "[diag] " so Loki filtering is a
# single `|= "[diag]"`. The tailer is backgrounded by run-job.sh before
# `exec ./run.sh`, so it lives for the lifetime of the Pod. On a host-
# side microVM teardown the tailer dies with the VM, but every line it
# already flushed to stdout is preserved on the host's
# /var/log/pods/<pod>/runner/0.log file that alloy-logs ships.

set -u

DIAG_DIR=${1:-/home/runner/actions-runner/_diag}

# Create the directory pre-emptively so `tail -F` can start watching
# before the runner writes its first log file. Failure is non-fatal:
# the directory will exist by the time the runner starts, and a stale
# read-only mount (which would block mkdir) is not a real concern in
# the kata pod shape.
mkdir -p "$DIAG_DIR" 2>/dev/null || true

# Track files we've already opened a tail on so the polling loop
# doesn't spawn duplicate `tail -F` per file.
declare -A SEEN

while :; do
  # Glob expansion handles "no files yet" — the literal pattern is
  # then a non-existent path which the `-f` check skips.
  for f in "$DIAG_DIR"/Runner_*.log "$DIAG_DIR"/Worker_*.log; do
    [ -f "$f" ] || continue
    if [ -z "${SEEN[$f]:-}" ]; then
      SEEN[$f]=1
      # `-F` (capital) follows by name and retries on rotation; the
      # runner doesn't rotate within a single job's lifetime, but using
      # -F over -f costs nothing and protects against future changes.
      # `-n +1` starts from the beginning of the file so we don't miss
      # lines written before the tail attached.
      # `sed -u` is line-buffered so each diag line reaches stdout
      # immediately instead of waiting for the default 4 KiB block to
      # fill — critical when the runner dies seconds after emitting
      # its last error.
      tail -F -n +1 "$f" 2>/dev/null | sed -u "s|^|[diag] |" &
    fi
  done
  sleep 2
done
