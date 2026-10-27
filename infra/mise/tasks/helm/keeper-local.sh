#!/usr/bin/env bash
#MISE description="Validate Keeper's local-volume migration and fail-closed state copy"
set -euo pipefail
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chart="$ROOT/infra/helm/tuist"

render() {
  helm template tuist "$chart" -n tuist \
    -f "$chart/values-managed-common.yaml" \
    -f "$chart/values-managed-production.yaml" \
    -f "$chart/values-ci.yaml" "$@" |
    yq -o json -I0 'select(.kind != null)' | jq -s .
}

render > "$WORK/default.json"
jq -e '[.[] | select(.kind == "StatefulSet" and (.metadata.name | endswith("-keeper")))][0] |
  .spec.volumeClaimTemplates[0].metadata.name == "data" and
  (.spec.template.spec.initContainers == null)' "$WORK/default.json" >/dev/null

local_args=(-f "$chart/values-keeper-local.yaml" --set 'clickhouse.managed.keeper.localVolume.nodeNames={keeper-a,keeper-b,keeper-c}')
render "${local_args[@]}" > "$WORK/migrate.json"
render "${local_args[@]}" --set clickhouse.managed.keeper.localVolume.migrateFromCloud=false > "$WORK/final.json"

for phase in migrate final; do
  jq -e '[.[] | select(.kind == "PersistentVolume" and (.metadata.name | contains("keeper-local")))] |
    length == 3 and all(.[]; .spec.persistentVolumeReclaimPolicy == "Retain" and
      .spec.local.path == "/var/lib/tuist/clickhouse-keeper" and
      .metadata.annotations["helm.sh/resource-policy"] == "keep") and
    (map(.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]) | unique | length == 3) and
    (map(.spec.claimRef.name) | unique | length == 3)' "$WORK/$phase.json" >/dev/null
  jq -e '[.[] | select(.kind == "StatefulSet" and (.metadata.name | endswith("-keeper")))][0] |
    .spec.updateStrategy.type == "OnDelete" and
    .spec.persistentVolumeClaimRetentionPolicy.whenDeleted == "Retain" and
    .spec.template.spec.containers[0].volumeMounts[1].name == "data-local" and
    (.spec.template.spec.containers[0].command[2] | contains(".tuist-keeper-member")) and
    (.spec.template.spec.containers[0].readinessProbe.exec.command[2] | contains("printf srvr"))' "$WORK/$phase.json" >/dev/null
  jq -e '[.[] | select(.kind == "PodDisruptionBudget" and (.metadata.name | endswith("-keeper")))][0].spec.minAvailable == 2' "$WORK/$phase.json" >/dev/null
done
jq -e '[.[] | select(.kind == "StatefulSet" and (.metadata.name | endswith("-keeper")))][0] |
  (.spec.volumeClaimTemplates | length == 2) and
  (.spec.template.spec.initContainers[0].volumeMounts[] | select(.name == "data") | .readOnly == true)' "$WORK/migrate.json" >/dev/null
jq -e '[.[] | select(.kind == "StatefulSet" and (.metadata.name | endswith("-keeper")))][0] |
  (.spec.volumeClaimTemplates | map(.metadata.name)) == ["data-local"] and
  .spec.template.spec.initContainers == null' "$WORK/final.json" >/dev/null

for nodes in '{keeper-a,keeper-a,keeper-c}' '{keeper-a,keeper-b}' '{}'; do
  if render -f "$chart/values-keeper-local.yaml" --set "clickhouse.managed.keeper.localVolume.nodeNames=$nodes" > /dev/null 2>&1; then
    echo "Invalid node mapping accepted: $nodes" >&2; exit 1
  fi
done
if render --set clickhouse.managed.keeper.localVolume.migrateFromCloud=true > /dev/null 2>&1; then
  echo 'Migration accepted without local storage' >&2; exit 1
fi

mkdir -p "$WORK/source/log" "$WORK/source/snapshots" "$WORK/target"
printf 'raft-log\n' > "$WORK/source/log/changelog.bin"
printf 'snapshot\n' > "$WORK/source/snapshots/snapshot.bin"
printf 'term-and-vote\n' > "$WORK/source/state"
copy_state() {
  HOSTNAME=keeper-1 KEEPER_SOURCE_DIR="$WORK/source" KEEPER_TARGET_DIR="$WORK/target" \
    bash "$chart/files/keeper-copy-state.sh"
}
copy_state
diff -r -x .tuist-keeper-member "$WORK/source" "$WORK/target"
[[ "$(cat "$WORK/target/.tuist-keeper-member")" == 1 ]]
printf 'newer-state\n' > "$WORK/target/state"
copy_state
[[ "$(cat "$WORK/target/state")" == newer-state ]]
printf '2\n' > "$WORK/target/.tuist-keeper-member"
if copy_state 2>/dev/null; then echo 'Wrong member accepted' >&2; exit 1; fi
rm "$WORK/target/.tuist-keeper-member"
if copy_state 2>/dev/null; then echo 'Partial copy accepted' >&2; exit 1; fi
rm -rf "$WORK/target"
mkdir "$WORK/target"
rm "$WORK/source/log/changelog.bin"
if copy_state 2>/dev/null; then echo 'Empty source accepted' >&2; exit 1; fi

echo 'Keeper local migration: render guards, retained volumes, staged claims and state-copy safety passed.'
