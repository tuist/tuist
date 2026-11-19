#!/usr/bin/env bash
#MISE description="Check per-pool Linux image holds without changing other pools"
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
chart="$root/infra/helm/tuist"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
desired="ghcr.io/tuist/tuist-linux-runner@sha256:$(printf 'a%.0s' {1..64})"
old_shape="ghcr.io/tuist/tuist-linux-runner@sha256:$(printf 'b%.0s' {1..64})"
old_explicit="ghcr.io/tuist/tuist-linux-runner@sha256:$(printf 'c%.0s' {1..64})"
for environment in staging canary production; do
  render() {
    helm template tuist "$chart" -f "$chart/values-managed-common.yaml" \
      -f "$chart/values-managed-$environment.yaml" -f "$chart/values-ci.yaml" \
      --set-string "runnersFleetLinux.shapeRunnerImage=$desired" \
      --set-json 'runnersFleetLinux.pools=[{"name":"staging-test","dispatchLabel":"staging-test","runtimeClass":"kata-qemu"}]' "$@" |
      yq -o=json -I=0 'select(.kind == "RunnerPool")' | jq -s .
  }
  render > "$work/desired.json"
  shape="$(jq -er '[.[]|select(.spec.os=="linux" and .metadata.labels["tuist.dev/shape"]!=null)][0].metadata.name' "$work/desired.json")"
  explicit="$(jq -er '.[]|select(.spec.dispatchLabel=="staging-test")|.metadata.name' "$work/desired.json")"
  jq -n --arg shape "$shape" --arg explicit "$explicit" --arg old_shape "$old_shape" --arg old_explicit "$old_explicit" \
    '{runnersFleetLinux:{imageHolds:{($shape):$old_shape,($explicit):$old_explicit}}}' > "$work/holds.json"
  render -f "$work/holds.json" > "$work/held.json"
  jq -en --slurpfile desired "$work/desired.json" --slurpfile held "$work/held.json" --slurpfile values "$work/holds.json" '
    ($desired[0] | map(.spec.image = ($values[0].runnersFleetLinux.imageHolds[.metadata.name] // .spec.image)) | sort_by(.metadata.name))
    == ($held[0] | sort_by(.metadata.name))' >/dev/null
  render -f "$work/holds.json" --set-json 'runnersFleetLinux.imageHolds={}' > "$work/released.json"
  jq -en --slurpfile desired "$work/desired.json" --slurpfile released "$work/released.json" '$desired == $released' >/dev/null
  echo "$environment: explicit and shape pools hold independently; macOS/other fields stay intact; clearing holds promotes."
done
