#!/usr/bin/env bash
set -euo pipefail

# Rolls the sandboxd DaemonSet's Pods once `sandboxes.vmm.inPlaceUpgrades`
# makes it OnDelete (step 2b of seamless daemon restarts).
#
# A Pod whose spec differs from the DaemonSet's only in the sandboxd
# container's image is upgraded in place: the updater arms a handover
# (an annotation naming the running container, see
# infra/sandboxd/cmd/sandboxd/handover.go), waits for the daemon to confirm
# it with the new configuration, and patches the container's image. The
# kubelet restarts only that container; the VMs stay in the vmm container and
# the new daemon re-attaches them. Any other difference (vmm's image, volumes,
# a first rollout) replaces the Pod, which pauses its sandboxes as before.
# A Pod on the current revision whose daemon loaded an older ConfigMap
# (`sandboxd_config_info`) restarts the same way: the kubelet refreshes the
# mounted file, but the daemon reads it only at startup. Its patch toggles
# the image between `<tag>` and `<tag>@<digest it runs>`, the same image, so
# the kubelet restarts the container for a spec change. A daemon that exited
# instead (a SIGTERM) would be restarted under the kubelet's crash back-off,
# which holds the second restart within ten minutes for 10 s or more.
#
# Pods are replaced, like they are upgraded in place, only once no restore
# still streams its disks or memory from the archive: such a sandbox cannot
# pause, and a daemon stopped under it leaves it in error.
#
# Remote execution workers (SANDBOXD_UPGRADE_REPLACE_IDLE_SECONDS) also wait
# before a replacement until the worker holds no VM, which happens about a
# minute after its last action: a replaced worker fails the actions it runs,
# and Bazel retries them. Past that wait it is replaced anyway. An in-place
# upgrade does not wait: its VMs survive, but an action executing in one
# fails as with a replacement (`exec` ends with the daemon's connection).
#
# Usage: sandboxd-upgrade.sh <namespace> <daemonset>
namespace=$1
daemonset=$2
container=sandboxd
annotation=sandboxes.tuist.dev/handover
# How long the updater waits for restores to stop receiving their disks or
# memory before it upgrades anyway (those sandboxes then pause and resume).
lazy_wait_seconds=${SANDBOXD_UPGRADE_LAZY_WAIT_SECONDS:-600}
# How long a replacement waits for the Pod to hold no sandbox; 0 does not.
idle_wait_seconds=${SANDBOXD_UPGRADE_REPLACE_IDLE_SECONDS:-0}
kubectl=${KUBECTL:-kubectl}
sleep_step=${SANDBOXD_UPGRADE_SLEEP:-5}

k() { "$kubectl" -n "$namespace" "$@"; }

ds=$(k get daemonset "$daemonset" -o json)
selector=$(jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")' <<< "$ds")
want_image=$(jq -r --arg c "$container" '.spec.template.spec.containers[] | select(.name == $c) | .image' <<< "$ds")
uid=$(jq -r '.metadata.uid' <<< "$ds")
# The newest ControllerRevision is the DaemonSet's current template.
revisions=$(k get controllerrevisions -o json)
current=$(jq -c --arg uid "$uid" '
  [.items[] | select(any(.metadata.ownerReferences[]?; .uid == $uid))]
  | max_by(.revision)' <<< "$revisions")
current_hash=$(jq -r '.metadata.labels."controller-revision-hash"' <<< "$current")
config_map=$(jq -r '.spec.template.spec.volumes[] | select(.name == "config") | .configMap.name' <<< "$ds")
want_config=$(k get configmap "$config_map" -o json | jq -j '.data."config.env"' | sha256sum | cut -d' ' -f1)

# A template without the sandboxd container's image and the DaemonSet's
# bookkeeping: equal for two revisions an in-place upgrade can move between.
normalize='del(."$patch") | del(.metadata.labels."controller-revision-hash")
  | .spec.containers |= map(if .name == $c then del(.image) else . end)'
want_spec=$(jq -cS --arg c "$container" ".spec.template | $normalize" <<< "$ds")

metrics() {
  k exec "$1" -c "$container" -- sh -c 'curl -fsS "http://$METRICS_ADDR/metrics"' 2>/dev/null || true
}

loaded_config() {
  metrics "$1" | sed -n 's/^sandboxd_config_info{sha256="\([0-9a-f]*\)"} .*/\1/p'
}

log_lines() { k logs "$1" -c "$container" --since="${2:-10m}" 2>/dev/null || true; }

# A Pod's image without the digest a config-only restart appended to its tag.
bare_image() {
  local ref=${1%@sha256:*}
  if [ "$ref" != "$1" ] && [[ ${ref##*/} == *:* ]]; then echo "$ref"; else echo "$1"; fi
}

wait_lazy() {
  local pod=$1 lazy
  for _ in $(seq 1 $((lazy_wait_seconds / sleep_step))); do
    lazy=$(metrics "$pod" | awk '/^sandboxd_handover_blocked\{reason="(lazy_disks|memory_loading)"\}/ {n += $2} END {print n + 0}')
    [ "${lazy:-0}" = 0 ] && return 0
    echo "$pod: $lazy sandboxes still receive their disks or memory; waiting"
    sleep "$sleep_step"
  done
}

# Three reads in a row without a sandbox, so one between two actions does
# not count. A daemon that reports none (unreachable) counts as busy.
wait_idle() {
  local pod=$1 held quiet=0
  [ "$idle_wait_seconds" -gt 0 ] || return 0
  for _ in $(seq 1 $((idle_wait_seconds / sleep_step))); do
    held=$(metrics "$pod" | awk '/^sandboxd_sandboxes\{/ {n += $2; seen = 1} END {if (seen) print n + 0}')
    if [ "$held" = 0 ]; then
      quiet=$((quiet + 1))
      [ "$quiet" -ge 3 ] && { echo "$pod holds no sandboxes"; return 0; }
    else
      quiet=0
      echo "$pod holds ${held:-unknown} sandboxes; waiting for it to drain"
    fi
    sleep "$sleep_step"
  done
  echo "::warning::$pod did not drain within ${idle_wait_seconds}s; replacing it anyway (its actions fail and are retried)"
}

wait_ready() {
  local pod=$1 old_id=$2
  for _ in $(seq 1 120); do
    status=$(k get pod "$pod" -o json | jq -c --arg c "$container" '.status.containerStatuses[]? | select(.name == $c)')
    id=$(jq -r '.containerID // ""' <<< "$status")
    if [ -n "$id" ] && [ "$id" != "$old_id" ] && [ "$(jq -r '.ready' <<< "$status")" = true ]; then
      return 0
    fi
    sleep "$sleep_step"
  done
  return 1
}

replace() {
  local pod=$1 node=$2
  wait_lazy "$pod"
  wait_idle "$pod"
  echo "Replacing $pod on $node (its sandboxes pause and resume)"
  k delete pod "$pod" --wait=true --timeout=180s
  new=""
  for _ in $(seq 1 60); do
    new=$(k get pods -l "$selector" --field-selector "spec.nodeName=$node" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [ -n "$new" ] && [ "$new" != "$pod" ] && break
    sleep "$sleep_step"
  done
  [ -n "$new" ] && [ "$new" != "$pod" ] || { echo "::error::No replacement sandboxd Pod on $node"; return 1; }
  k wait --for=condition=Ready "pod/$new" --timeout=10m
}

# upgrade_in_place <pod> <node> <container id> <image to patch in | "" to SIGTERM>
upgrade_in_place() {
  local pod=$1 node=$2 old_id=$3 image=$4
  wait_lazy "$pod"
  nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
  until=$(date -u -d "+5 minutes" +%Y-%m-%dT%H:%M:%SZ)
  marker=$(jq -cn --arg c "$old_id" --arg u "$until" --arg n "$nonce" '{container: $c, until: $u, nonce: $n}')
  k annotate pod "$pod" --overwrite "$annotation=$marker" >/dev/null
  # The kubelet refreshes the annotation and the ConfigMap files on its own
  # schedule (about a minute); patch only once the daemon has both.
  armed=false
  for _ in $(seq 1 $((180 / sleep_step))); do
    if log_lines "$pod" 5m | jq -Rre --arg n "$nonce" --arg sum "$want_config" \
      'fromjson? | select(.msg == "handover armed" and .nonce == $n and .config_sha256 == $sum)' >/dev/null; then
      armed=true
      break
    fi
    sleep "$sleep_step"
  done
  if [ "$armed" != true ]; then
    echo "::warning::$pod did not arm its handover; replacing it instead"
    k annotate pod "$pod" "$annotation-" >/dev/null || true
    replace "$pod" "$node"
    return
  fi
  if [ -n "$image" ]; then
    k patch pod "$pod" --type=strategic -p "$(jq -cn --arg c "$container" --arg i "$image" --arg h "$current_hash" \
      '{metadata: {labels: {"controller-revision-hash": $h}}, spec: {containers: [{name: $c, image: $i}]}}')" >/dev/null
  else
    # Only when the image cannot carry a digest; see the header.
    # The Pod shares one PID namespace, so PID 1 is the pause container.
    k exec "$pod" -c "$container" -- sh -c 'kill -TERM $(pidof sandboxd)' >/dev/null
  fi
  if ! wait_ready "$pod" "$old_id"; then
    echo "::error::$pod's sandboxd did not come back ready on $want_image"
    k logs "$pod" -c "$container" --tail=80 || true
    return 1
  fi
  k annotate pod "$pod" "$annotation-" >/dev/null || true
  log=$(log_lines "$pod" 5m)
  attached=$(jq -Rr 'fromjson? | select(.msg == "sandbox re-attached") | .sandbox' <<< "$log" | wc -l)
  lost=$(jq -Rr 'fromjson? | select(.msg | test("handed-over|re-attaching")) | .sandbox' <<< "$log" | wc -l)
  echo "$pod: $attached sandboxes re-attached, $lost cold boot"
  if [ "$lost" -gt 0 ]; then
    echo "::warning::$pod: $lost handed-over sandboxes could not be re-attached and cold boot on their next resume"
  fi
}

pods=$(k get pods -l "$selector" -o json)
rolled=0
while IFS='|' read -r -u 3 pod node hash old_id image image_id; do
  [ -n "$pod" ] || continue
  if [ "$hash" = "$current_hash" ] && [ "$(bare_image "$image")" = "$want_image" ]; then
    loaded=$(loaded_config "$pod")
    if [ -z "$loaded" ]; then
      echo "::warning::$pod does not report the configuration it loaded; leaving it"
    elif [ "$loaded" != "$want_config" ] && [ -n "$old_id" ]; then
      rolled=$((rolled + 1))
      echo "Restarting $pod's daemon on $node in place for its new configuration"
      digest=${image_id##*@}
      if [ "$image" != "$want_image" ]; then
        restart_image=$want_image
      elif [[ $want_image != *@* && $digest == sha256:* ]]; then
        restart_image=$want_image@$digest
      else
        restart_image=""
      fi
      upgrade_in_place "$pod" "$node" "$old_id" "$restart_image"
    fi
    continue
  fi
  have_spec=$(jq -cS --arg c "$container" --arg h "$hash" \
    ".items[] | select(.metadata.labels.\"controller-revision-hash\" == \$h) | .data.spec.template | $normalize" <<< "$revisions" | head -n1)
  rolled=$((rolled + 1))
  if [ -n "$have_spec" ] && [ "$have_spec" = "$want_spec" ] && [ -n "$old_id" ]; then
    echo "Upgrading $pod on $node in place to $want_image"
    upgrade_in_place "$pod" "$node" "$old_id" "$want_image"
  else
    replace "$pod" "$node"
  fi
done 3< <(jq -r --arg c "$container" '.items[]
  | [.metadata.name, .spec.nodeName, .metadata.labels."controller-revision-hash",
     ([.status.containerStatuses[]? | select(.name == $c) | .containerID][0] // ""),
     ([.spec.containers[] | select(.name == $c) | .image][0]),
     ([.status.containerStatuses[]? | select(.name == $c) | .imageID][0] // "")]
  | join("|")' <<< "$pods")
echo "Rolled $rolled sandboxd Pods to revision $current_hash"
