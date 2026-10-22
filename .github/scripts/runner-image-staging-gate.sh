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
# so no job waits on the pull. It moves regardless once the announcement is
# older than RUNNER_IMAGE_STAGING_TIMEOUT_SECONDS (an hour), or when the
# announcement says `tuist.dev/runner-image-staging: skip`, does not name the
# new image, or no host holds the current one.
#
# Usage: runner-image-staging-gate.sh <digests-json> <stacked-digests-json>
#   Both map an Xcode version to a manifest digest, as the deploy passes them
#   to `runnersFleet.runnerImageDigests` and
#   `runnersFleet.runnerImageStackedDigests`. Prints
#   {"digests": {...}, "stacked": {...}} with each held Xcode set back to the
#   digest its pools run now, and says on stderr what it held and why.
#   Reads the cluster through kubectl's current context.
set -euo pipefail

digests="${1:?usage: runner-image-staging-gate.sh <digests-json> <stacked-digests-json>}"
stacked="${2:?usage: runner-image-staging-gate.sh <digests-json> <stacked-digests-json>}"
timeout="${RUNNER_IMAGE_STAGING_TIMEOUT_SECONDS:-3600}"
now="${NOW:-$(date -u +%s)}"

pools="$(kubectl get runnerpools.tuist.dev --all-namespaces -l tuist.dev/runner-image-variant -o json)"
nodes="$(kubectl get nodes -o json)"
announcements="$(kubectl get configmaps --all-namespaces -l tuist.dev/upcoming-runner-images=true -o json)"

golden_label() {
  local sum
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(printf '%s' "$1" | sha256sum)"
  else
    sum="$(printf '%s' "$1" | shasum -a 256)"
  fi
  echo "tuist.dev/golden-${sum:0:16}"
}

transitions="$(jq -r --argjson standalone "$digests" --argjson stacked "$stacked" '
  [.items[] | {
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
  | [.xcode, .variant, .current, .next] | @tsv' <<< "$pools")"

holds='[]'
while IFS=$'\t' read -r xcode variant current next; do
  [ -n "$xcode" ] || continue
  announcement="$(jq -r --arg key "${xcode}.${variant}" --arg next "$next" '
    [.items[] | select(.data[$key] == $next)] | first
    | if . == null then "none"
      else [
        (.metadata.annotations["tuist.dev/runner-image-staging"] // "wait"),
        ((.metadata.annotations["tuist.dev/runner-image-announced-at"] // "") | try fromdateiso8601 catch 0)
      ] | @tsv
      end' <<< "$announcements")"
  if [ "$announcement" = "none" ]; then
    echo "Xcode $xcode ($variant): no announcement names $next; moving." >&2
    continue
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
