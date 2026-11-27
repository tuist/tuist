#!/usr/bin/env bash
#
# Holds each catalog RunnerPool on its current runner image until the hosts
# that serve it have staged the image a release moves it to.
#
# A release announces its images (the `tuist-upcoming-runner-images`
# ConfigMap, written by runner-image-release.yml) and every macOS host pulls
# the next image of the pools it serves in the background, advertising each
# golden it holds as the Node label `tuist.dev/golden-<first 16 hex of
# sha256(image ref)>` (infra/tart-kubelet). A pool moves once every Ready,
# schedulable Node holding its current image's golden also holds the new one,
# so no job waits on the pull. It moves regardless once the new image was
# announced more than RUNNER_IMAGE_STAGING_TIMEOUT_SECONDS (an hour) ago, when
# the announcement says `tuist.dev/runner-image-staging: skip`, or when no host
# holds the current image.
#
# The hour counts from when the announcement first named the new image
# (`tuist.dev/runner-image-announced-at-by-image`, one time per key), falling
# back to the ConfigMap's `tuist.dev/runner-image-announced-at`. When no
# announcement names the new image (a release overwrote a tag after
# announcing it, a release's announce job failed, a rollback), the gate
# announces it itself into the pool's namespace and holds the pool, so the
# hosts stage it and a later deploy moves the pool within the hour.
#
# Usage: runner-image-staging-gate.sh <digests-json> <stacked-digests-json>
#   Both map an Xcode version to a manifest digest, as the deploy passes them
#   to `runnersFleet.runnerImageDigests` and
#   `runnersFleet.runnerImageStackedDigests`. Prints
#   {"digests": {...}, "stacked": {...}} with each held Xcode set back to the
#   digest its pools run now, and says on stderr what it held and why.
#   Reads the cluster through kubectl's current context, and patches the
#   announcement ConfigMap when it announces an image.
set -euo pipefail

digests="${1:?usage: runner-image-staging-gate.sh <digests-json> <stacked-digests-json>}"
stacked="${2:?usage: runner-image-staging-gate.sh <digests-json> <stacked-digests-json>}"
timeout="${RUNNER_IMAGE_STAGING_TIMEOUT_SECONDS:-3600}"
now="${NOW:-$(date -u +%s)}"

pools="$(kubectl --request-timeout=30s get runnerpools.tuist.dev --all-namespaces -l tuist.dev/runner-image-variant -o json)"
nodes="$(kubectl --request-timeout=30s get nodes -o json)"
announcements="$(kubectl --request-timeout=30s get configmaps --all-namespaces -l tuist.dev/upcoming-runner-images=true -o json)"

golden_label() {
  local sum
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(printf '%s' "$1" | sha256sum)"
  else
    sum="$(printf '%s' "$1" | shasum -a 256)"
  fi
  echo "tuist.dev/golden-${sum:0:16}"
}

announcement_name=tuist-upcoming-runner-images
announced_by_image=tuist.dev/runner-image-announced-at-by-image

# Names $3 under key $2 in namespace $1's announcement ConfigMap, stamped with
# the gate's time, and records the write in $announcements so later keys of
# this run merge with it. A merge patch leaves the release's keys and field
# ownership alone; the release's next server-side apply takes these keys over.
announce() {
  local namespace="$1" key="$2" image="$3" existing times patch
  existing="$(jq -c --arg ns "$namespace" --arg name "$announcement_name" \
    '[.items[] | select(.metadata.namespace == $ns and .metadata.name == $name)] | first' <<< "$announcements")"
  times="$(jq -c --arg ann "$announced_by_image" --arg key "$key" --argjson now "$now" '
    ((.metadata.annotations[$ann] // "{}") | try fromjson catch {}) + {($key): ($now | todate)}' <<< "$existing")"
  patch="$(jq -cn --arg ann "$announced_by_image" --arg times "$times" --arg key "$key" --arg image "$image" '{
    metadata: {labels: {"tuist.dev/upcoming-runner-images": "true"}, annotations: {($ann): $times}},
    data: {($key): $image}}')"
  if [ "$existing" = "null" ]; then
    jq -c --arg ns "$namespace" --arg name "$announcement_name" \
      '. + {apiVersion: "v1", kind: "ConfigMap"} | .metadata += {namespace: $ns, name: $name}' <<< "$patch" |
      kubectl --request-timeout=30s create -f - >/dev/null
    existing="$(jq -c --arg ns "$namespace" --arg name "$announcement_name" '.metadata += {namespace: $ns, name: $name}' <<< "$patch")"
  else
    kubectl --request-timeout=30s --namespace "$namespace" patch configmap "$announcement_name" --type merge -p "$patch" >/dev/null
  fi
  announcements="$(jq -c --arg ns "$namespace" --arg name "$announcement_name" --argjson existing "$existing" --argjson patch "$patch" '
    .items = ([.items[] | select(.metadata.namespace != $ns or .metadata.name != $name)]
      + [$existing * $patch])' <<< "$announcements")"
}

transitions="$(jq -r --argjson standalone "$digests" --argjson stacked "$stacked" '
  [.items[] | {
    namespace: .metadata.namespace,
    xcode: .metadata.labels["tuist.dev/xcode-version"],
    variant: .metadata.labels["tuist.dev/runner-image-variant"],
    current: .spec.image
  }]
  | unique[]
  | select(.current | test("@sha256:[a-f0-9]{64}$"))
  | .digest = ((if .variant == "stacked" then $stacked else $standalone end)[.xcode] // "")
  | select(.digest != "")
  | .next = (.current | sub("@sha256:[a-f0-9]{64}$"; "")) + "@" + .digest
  | select(.next != .current)
  | [.namespace, .xcode, .variant, .current, .next] | @tsv' <<< "$pools")"

holds='[]'
while IFS=$'\t' read -r namespace xcode variant current next; do
  [ -n "$xcode" ] || continue
  key="${xcode}.${variant}"
  announcement="$(jq -r --arg key "$key" --arg next "$next" --arg ann "$announced_by_image" '
    [.items[] | select(.data[$key] == $next)] | first
    | if . == null then "none"
      else [
        (.metadata.annotations["tuist.dev/runner-image-staging"] // "wait"),
        (((.metadata.annotations[$ann] // "{}") | try fromjson catch {})[$key]
          // .metadata.annotations["tuist.dev/runner-image-announced-at"] // ""
          | try fromdateiso8601 catch 0)
      ] | @tsv
      end' <<< "$announcements")"
  if [ "$announcement" = "none" ]; then
    echo "Xcode $xcode ($variant): no announcement names $next; announcing it." >&2
    announce "$namespace" "$key" "$next"
    announcement="$(printf 'wait\t%s' "$now")"
  fi
  IFS=$'\t' read -r staging announced_at <<< "$announcement"
  if [ "$staging" = "skip" ]; then
    echo "Xcode $xcode ($variant): the release skips staging; moving." >&2
    continue
  fi
  if [ $((now - announced_at)) -ge "$timeout" ]; then
    echo "Xcode $xcode ($variant): announced over ${timeout}s ago; moving without waiting for hosts." >&2
    continue
  fi
  missing="$(jq -r --arg current "$(golden_label "$current")" --arg next "$(golden_label "$next")" '
    [.items[]
      | select(.spec.unschedulable != true)
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
      | select(.metadata.labels[$current] != null and .metadata.labels[$next] == null)
      | .metadata.name]
    | join(" ")' <<< "$nodes")"
  if [ -z "$missing" ]; then
    echo "Xcode $xcode ($variant): every host serving it holds $next; moving." >&2
    continue
  fi
  echo "Xcode $xcode ($variant): holding on $current; still staging $next on: $missing" >&2
  holds="$(jq -c --arg xcode "$xcode" --arg variant "$variant" --arg digest "${current##*@}" \
    '. + [{xcode: $xcode, variant: $variant, digest: $digest}]' <<< "$holds")"
done <<< "$transitions"

jq -cn --argjson standalone "$digests" --argjson stacked "$stacked" --argjson holds "$holds" '
  reduce $holds[] as $hold ({digests: $standalone, stacked: $stacked};
    if $hold.variant == "stacked" then .stacked[$hold.xcode] = $hold.digest
    else .digests[$hold.xcode] = $hold.digest end)'
