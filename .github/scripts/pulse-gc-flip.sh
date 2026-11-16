#!/usr/bin/env bash
# Turns object-storage GC on or off for a Pulse cluster (cluster.gc.environments)
# with a coordinated stop instead of a rolling restart. A datanode checks its GC
# setting against metasrv's when it opens a heartbeat stream: a mismatched one
# is refused, its lease lapses and its regions turn read-only, and writes to
# them fail with a 4xx that remote write does not retry. With held datanodes
# (cluster.datanode.drainedRolloutEnvironments) the mismatch would last the
# whole drained rollout, and the drain itself needs heartbeats. So the deploy:
#
#   begin    turns on metasrv maintenance mode, which stops region failover
#            (and GC) while heartbeats fail
#   (deploy) upgrades with cluster.frontend.stopped=true: metasrv restarts on
#            the new setting and writers queue and retry against no frontends
#   finish   restarts every datanode at once on the new setting, checks they
#            heartbeat, and turns maintenance mode off
#   (deploy) upgrades again, which brings the frontends back
#
# `needed <resources.json>` prints true when the rendered metasrv GC setting
# differs from the live one, or when maintenance mode is still on from an
# interrupted flip, so rerunning the deploy resumes it.
set -euo pipefail
mode=${1:?usage: pulse-gc-flip.sh needed <resources.json>|begin|finish}
namespace=${PULSE_NAMESPACE:-observability}
k() { kubectl -n "$namespace" "$@"; }
gc_on() { grep -qzP '\[gc\]\nenable = true\n'; }
# Maintenance mode lives in etcd; any metasrv serves it. Each one caches it
# for 10 s, so callers wait before relying on a change.
maintenance() {
  k exec deploy/pulse-metasrv -c metasrv -- \
    curl -sS --fail --max-time 10 "$@" "http://localhost:4000/admin/maintenance/${action:-status}"
}

case $mode in
  needed)
    resources=${2:?usage: pulse-gc-flip.sh needed <resources.json>}
    if ! k get configmap pulse-metasrv-config > /dev/null 2>&1; then
      echo false
      exit 0
    fi
    rendered=false live=false
    jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "pulse-metasrv-config") | .data["config.toml"]' \
      "$resources" | gc_on && rendered=true
    k get configmap pulse-metasrv-config -o json | jq -r '.data["config.toml"]' | gc_on && live=true
    if [[ $rendered != "$live" ]] || maintenance | jq -e .enabled > /dev/null; then
      echo true
    else
      echo false
    fi
    ;;
  begin)
    action=enable maintenance -X POST
    echo
    sleep 15
    echo "Metasrv maintenance mode is on; stopping frontends for the GC switch." | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    ;;
  finish)
    replicas=$(k get statefulset pulse-datanode -o jsonpath='{.spec.replicas}')
    started=$(date -u +%FT%TZ)
    # Every datanode restarts together: the StatefulSet is Parallel, and the
    # next upgrade holds the partition again.
    k patch statefulset pulse-datanode --type merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
    # Waiting for the deletion keeps a resumed switch, whose datanodes may
    # already be on the update revision, from reading the old pods as rolled.
    k delete pod -l app.kubernetes.io/instance=pulse,app.kubernetes.io/component=datanode --wait=true --timeout=300s
    k rollout status statefulset/pulse-datanode --timeout=900s
    # Readiness follows region opening (init_regions_in_background = false).
    # Give heartbeats a few intervals to fail before checking they did not.
    sleep 30
    for ((i = 0; i < replicas; i++)); do
      if k logs "pulse-datanode-$i" --since-time="$started" | grep -q 'GC configuration mismatch'; then
        echo "::error::pulse-datanode-$i still disagrees with metasrv on GC; maintenance mode stays on. Rerun the deploy to resume."
        exit 1
      fi
    done
    action=disable maintenance -X POST
    echo
    sleep 15
    echo "Datanodes restarted on the new GC setting; maintenance mode is off." | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
