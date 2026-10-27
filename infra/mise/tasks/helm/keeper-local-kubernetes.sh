#!/usr/bin/env bash
#MISE description="Rehearse Keeper StatefulSet storage handoffs in a disposable kind cluster"
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
WORK=$(mktemp -d /tmp/keeper-kind.XXXXXX)
export KUBECONFIG="$WORK/kubeconfig"
cluster="keeper-rehearsal-$$"
export KEEPER=tuist-tuist-clickhouse-keeper
cleanup() { kind delete cluster --name "$cluster"; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir "$WORK/legacy"
cat > "$WORK/kind.yaml" <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
YAML
for i in 1 2 3; do
  cat >> "$WORK/kind.yaml" <<YAML
  - role: worker
    extraMounts:
      - hostPath: $WORK/legacy
        containerPath: /keeper-test-legacy
YAML
done
kind create cluster --name "$cluster" --image kindest/node:v1.34.0 --config "$WORK/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 120s
kind load docker-image clickhouse/clickhouse-server:26.3 --name "$cluster"
kubectl create namespace tuist
kubectl label nodes -l '!node-role.kubernetes.io/control-plane' node.cluster.x-k8s.io/pool=keeper
chart="$ROOT/infra/helm/tuist"
render() {
  helm template tuist "$chart" -n tuist -f "$chart/values-managed-common.yaml" -f "$chart/values-managed-production.yaml" -f "$chart/values-ci.yaml" \
    --set clickhouse.managed.keeper.nodeSelector.node\\.cluster\\.x-k8s\\.io/pool=keeper \
    --set clickhouse.managed.keeper.storageClassName=keeper-test-cloud \
    "$@" | yq 'select(.metadata.name | test("^" + strenv(KEEPER)))'
}
render > "$WORK/old.yaml"
# Simulated old disks are visible at the same path on every disposable node.
# This tests controller handoff and copying, not a real CSI detach/attach.
for i in 0 1 2; do
  cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: keeper-test-cloud-$i
spec:
  capacity: {storage: 10Gi}
  accessModes: [ReadWriteOnce]
  storageClassName: keeper-test-cloud
  persistentVolumeReclaimPolicy: Retain
  claimRef: {namespace: tuist, name: data-$KEEPER-$i}
  hostPath: {path: /keeper-test-legacy/$i, type: DirectoryOrCreate}
YAML
done
kubectl -n tuist apply -f "$WORK/old.yaml"
kubectl -n tuist rollout status sts/"$KEEPER" --timeout=180s
# Reuse the three test workers without colliding with another member's required
# anti-affinity. Production uses three fresh dedicated nodes instead.
nodes=$(kubectl -n tuist get pods -l app.kubernetes.io/component=clickhouse-keeper -o json | jq -r '[.items[]] | sort_by(.metadata.name) | map(.spec.nodeName) | join(",")')
render -f "$chart/values-keeper-local.yaml" --set "clickhouse.managed.keeper.localVolume.nodeNames={$nodes}" > "$WORK/migrate.yaml"
render -f "$chart/values-keeper-local.yaml" --set "clickhouse.managed.keeper.localVolume.nodeNames={$nodes}" --set clickhouse.managed.keeper.localVolume.migrateFromCloud=false > "$WORK/final.yaml"
query() { kubectl -n tuist exec "$KEEPER-$1" -c keeper -- clickhouse keeper-client --host 127.0.0.1 --query "$2"; }
query 0 'create /migration-test before'
for phase in migrate final; do
  yq 'select(.kind != "StatefulSet")' "$WORK/$phase.yaml" | kubectl -n tuist apply -f -
  kubectl -n tuist wait jobs --all --for=condition=complete --timeout=120s
  old_uids=$(kubectl -n tuist get pods -l app.kubernetes.io/component=clickhouse-keeper -o json | jq -r '[.items[].metadata.uid] | sort | join(",")')
  kubectl -n tuist delete sts "$KEEPER" --cascade=orphan
  yq 'select(.kind == "StatefulSet")' "$WORK/$phase.yaml" | kubectl -n tuist apply -f -
  new_uids=$(kubectl -n tuist get pods -l app.kubernetes.io/component=clickhouse-keeper -o json | jq -r '[.items[].metadata.uid] | sort | join(",")')
  [[ "$old_uids" == "$new_uids" ]]
  for i in 0 1 2; do
    uid=$(kubectl -n tuist get pod "$KEEPER-$i" -o jsonpath='{.metadata.uid}')
    kubectl -n tuist delete pod "$KEEPER-$i" --wait=true
    for ((attempt = 0; attempt < 90; attempt++)); do
      new_uid=$(kubectl -n tuist get pod "$KEEPER-$i" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
      [[ -n "$new_uid" && "$new_uid" != "$uid" ]] && break
      sleep 1
    done
    kubectl -n tuist wait pod "$KEEPER-$i" --for=condition=Ready --timeout=180s
    [[ "$(query "$i" 'get /migration-test')" == before ]]
    for member in 0 1 2; do query "$member" "set /migration-test before"; done
    echo "$phase: member $i ready, metadata preserved, all members accept writes"
  done
done
kubectl -n tuist get pods -o json | jq -e '[.items[] | select(.metadata.name | test("keeper-[0-2]$"))] | length == 3 and all(.[]; ([.spec.volumes[] | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName] | length == 1) and .spec.initContainers == null)'
echo 'Kubernetes adoption, both rolling handoffs, actual readiness and cloud-free mounts passed.'
