# Move Keeper from Cloud Volumes to local disks

Keeper stores the replication metadata that the ClickHouse replicas need to
accept writes. Moving ClickHouse's data to local disks did not remove its
dependency on the three Keeper Cloud Volumes. During the October 27 incident,
all three Keeper hosts showed increased fsync latency alongside PostgreSQL
storage stalls; ClickHouse lost ready endpoints. Shared storage degradation is
the working diagnosis, not a confirmed provider root cause.

This migration preserves the three member IDs, DNS names, configuration and
ClickHouse metadata. It copies each **stopped** member's entire coordination
directory to a different local disk, then lets that member catch up from its
peers. Do not change membership or the ClickHouse version during the migration.

## Prerequisites and deployment boundary

1. Merge the additive infrastructure change first. Production's `md-keeper`
   provisions three dedicated ccx13 VMs in a spread placement group in fsn1.
   The normal Helm values still use Cloud Volumes. Verify three Ready nodes
   labeled `node.cluster.x-k8s.io/pool=keeper`, their distinct placement, free
   disk space, and the `tuist.dev/keeper=true:NoSchedule` taint. Record the
   exact hostname label for each ordinal; do not use the examples from tests.
   Target nodes must not already host another Keeper member: required
   anti-affinity would prevent the replacement from scheduling there.
2. This removes the Cloud Volume dependency, not the fsn1 or Hetzner compute
   failure domain. The local directory is on the VM's OS disk. PV capacity
   is a scheduling declaration, not a filesystem quota. Monitor disk space
   and fsync latency. Node deletion destroys the disk.
3. Schedule a window with deployment automation paused for this environment.
   Keep it paused through both StatefulSet handoffs and the final environment
   values change. Record the deployed release revision, image digest, current
   StatefulSet/ConfigMap/PVC/PV specs and ordinal-to-node mapping. Do not print
   Helm release Secrets or application credentials into logs.
4. Obtain human-driven production elevation covering Keeper ConfigMap,
   StatefulSet, pod and storage preparation changes, including cluster-scoped
   PV/StorageClass creation. Ordinary namespace edit access may not cover the
   latter; have an authorized human perform those scoped operations if needed.
   Follow `infra/AGENTS.md`; an agent must not drive `/elevate` or approve it.
5. Require a healthy three-member ensemble before starting: exactly one leader,
   two followers, both followers caught up, no growing outstanding queue and
   successful read/write operations. Both ClickHouse replicas must be Ready.
   A storage incident still preventing quorum is a recovery task, not a safe
   rolling migration window. Do not use `ruok` alone as this gate.
6. Take and verify a recoverable Keeper snapshot/log backup, including Raft
   state, using the running version's backup procedure. Preserve original cloud
   PVCs and record their volume IDs. Never delete or restore all members at once.

## Render only the Keeper resources

Run from the repository root. Use the same chart revision and environment
values as the currently deployed release plus this change. The CI overlay below
only satisfies image checks in unrelated templates, which the strict resource
filter discards; it does not override the Keeper image. Never apply the full
unfiltered render or alter replica counts. Create `/tmp/keeper-nodes.yaml` containing the
three real hostname labels in ordinal order:

```yaml
clickhouse:
  managed:
    keeper:
      localVolume:
        nodeNames:
          - REPLACE_WITH_NODE_FOR_ORDINAL_0
          - REPLACE_WITH_NODE_FOR_ORDINAL_1
          - REPLACE_WITH_NODE_FOR_ORDINAL_2
```

```bash
export KEEPER=tuist-tuist-clickhouse-keeper
export KEEPER_NAMESPACE=tuist
render_keeper() {
  helm template tuist infra/helm/tuist --namespace "$KEEPER_NAMESPACE" \
    -f infra/helm/tuist/values-managed-common.yaml \
    -f infra/helm/tuist/values-managed-production.yaml \
    -f infra/helm/tuist/values-ci.yaml \
    -f infra/helm/tuist/values-keeper-local.yaml \
    -f /tmp/keeper-nodes.yaml "$@" |
    yq 'select(
      (.kind == "ConfigMap" and .metadata.name == strenv(KEEPER) + "-config") or
      (.kind == "StatefulSet" and .metadata.name == strenv(KEEPER)) or
      (.kind == "PodDisruptionBudget" and .metadata.name == strenv(KEEPER)) or
      (.kind == "StorageClass" and .metadata.name == strenv(KEEPER) + "-local") or
      (.kind == "PersistentVolume" and (.metadata.name | test("^" + strenv(KEEPER) + "-local-"))) or
      (.kind == "Job" and (.metadata.name | test("^" + strenv(KEEPER) + "-prepare-")))
    ) |
    .metadata.annotations."meta.helm.sh/release-name" = "tuist" |
    .metadata.annotations."meta.helm.sh/release-namespace" = strenv(KEEPER_NAMESPACE) |
    .metadata.labels."app.kubernetes.io/managed-by" = "Helm"'
}
render_keeper > /tmp/keeper-migrate.yaml
render_keeper --set clickhouse.managed.keeper.localVolume.migrateFromCloud=false \
  > /tmp/keeper-final.yaml
```

Review both manifests. Only Keeper resources may be present; server, database
Secrets and ClickHouse data StatefulSets must be absent. Confirm identical Raft
configuration, member IDs and image digest, `OnDelete`, a PDB requiring two
members, retained PVCs/PVs, the exact node mapping, and the original `data`
claim template preserved in the migration manifest. Diff the new StatefulSet
against the live one for unrelated changes before proceeding.

## First handoff: copy one member at a time

Kubernetes cannot change a StatefulSet's volume claim templates in place.
Do not use `helm upgrade --force`, scale to zero, or delete the whole ensemble.

1. Apply the migration ConfigMap, StorageClass, PVs, PDB and preparation Jobs
   (all resources except the StatefulSet). Wait for all preparation Jobs to
   complete and check their disk-space output. They only create/chown the
   local directory; they do not format or erase disks.
2. Orphan-delete **only** the Keeper StatefulSet, leaving all three existing
   pods running, and immediately recreate it from the migration manifest:

   ```bash
   yq 'select(.kind != "StatefulSet")' /tmp/keeper-migrate.yaml |
     kubectl --context tuist-k8s-production -n tuist apply -f -
   # Wait for and inspect all three preparation Jobs before continuing.
   kubectl --context tuist-k8s-production -n tuist delete statefulset "$KEEPER" --cascade=orphan
   yq 'select(.kind == "StatefulSet")' /tmp/keeper-migrate.yaml |
     kubectl --context tuist-k8s-production -n tuist apply -f -
   ```

3. Verify all old pods are adopted by the new StatefulSet UID and none restarted.
   `OnDelete` is mandatory: it prevents the controller from advancing for you.
   The controller can report immutable-pod `FailedUpdate` events while adopted
   pods still have the old volume list; those pods keep running until their
   explicit replacement. Verify ownership and health rather than treating
   those events as permission to delete additional pods.
4. Choose a follower first. Record its pod UID and node. Gracefully delete that
   **one pod** with `kubectl delete pod`; never force-delete it. Pod deletion
   bypasses the PDB, so the operator must enforce the one-member limit. Wait
   for termination and cloud-volume detachment before accepting the replacement.
5. The replacement schedules onto its reserved local PV's node and temporarily
   attaches its original cloud PVC read-only. Its init container copies the
   entire stopped state, syncs it, then writes an ordinal marker. Inspect the
   init log, new pod UID, PV bindings, mounts and node assignment. A partial
   copy without a marker fails closed; stop and inspect it rather than adding
   a marker or erasing data blindly.
6. Require the member to rejoin, catch up and serve reads. Inspect `srvr`, `mntr`
   and `lgif` on all members: one leader, two followers, two synced followers
   reported by the leader, and committed log indices converging. Verify a
   temporary Keeper znode can be written and read through each member, then
   delete it. Also verify application ingestion, both ClickHouse readiness
   probes and replication queues. A Kubernetes Ready condition alone is not
   sufficient. Use the existing operator identity for database checks.
7. Repeat for the other follower, then the remaining member (re-evaluate leader
   roles first). Wait for full health after every replacement. A leader restart
   can cause a brief election and retries; this is not a zero-interruption promise.

## Second handoff: remove Cloud Volume mounts

After all three members use local data, orphan/recreate the StatefulSet again
using `/tmp/keeper-final.yaml`, with `migrateFromCloud=false`. This removes the
legacy claim template and copy init container. Verify adoption, then gracefully
replace one pod at a time with the same health gates. A member must start from
its existing local directory and marker without any cloud volume attached.
Keep old cloud PVCs retained and unmounted during the observation window.

Persist `nodeSelector`, `tolerations`, `localVolume.enabled=true`, the exact
ordered `nodeNames`, and `migrateFromCloud=false` in the production environment
values. Merge that final values change before resuming normal deployments.
The next Helm deployment must adopt the prepared resources and render the
same final StatefulSet. Confirm Helm reconciliation succeeds without restarts
or claim changes. Do not leave the temporary overlay as the only record of the
live topology. Leave `OnDelete` enabled; future Keeper upgrades require an
explicit, gated member-by-member restart.

## Failure and recovery

- Stop advancing on any failed health gate. Preserve the two healthy members.
  Original cloud disks become stale as soon as a member writes to its local
  disk. A generic Helm rollback or reattaching all old PVCs can restore stale
  metadata and is not a rollback procedure.
- If a member has not yet started on its new disk, its stopped original disk
  remains its valid source. Inspect partial-copy failures while that member is
  stopped. If it has started, repair or recopy its **latest** stopped state;
  never overlay the original source onto it. Rehearse any reverse migration
  separately and preserve quorum throughout.
- Missing local storage fails startup rather than creating an empty ensemble.
  PV node affinity intentionally prevents automatic rescheduling to another
  machine. The node pool disables automatic remediation and uses `OnDelete`
  upgrades. Keep the three-node pool size fixed; do not drain/delete multiple
  machines or let a node replacement silently reinitialize their state.
- A lost node needs an explicit one-member replacement and supported Keeper
  recovery from the surviving quorum, a new local PV/claim binding and updated
  node mapping. PV node affinity is immutable. Do not just relabel the empty
  replacement or manufacture the marker. Loss of quorum requires a separate
  disaster-recovery procedure from verified state; do not force a new quorum
  as part of this migration.

## Validation

`infra/mise/tasks/helm/keeper-local.sh` checks default, migration and final Helm
renders, invalid mappings, retained storage and state-copy failure behavior.
`infra/mise/tasks/helm/keeper-local-rehearsal.sh` starts three disposable Keeper
containers, writes metadata while each member is stopped, copies its state,
checks catch-up, deletes all original test disks and restarts the local members.
`infra/mise/tasks/helm/keeper-local-kubernetes.sh` additionally uses a disposable
four-node kind cluster to exercise the rendered StatefulSets, pod adoption,
both handoffs, readiness and final cloud-free mounts. It needs Docker, kind,
kubectl, Helm, yq and jq. It isolates its kubeconfig and deletes its test cluster
on exit. Its original volumes use a shared host directory to simulate disks
that can move between nodes. These tests do not exercise real CSI detach/attach,
CAPI provisioning, physical host loss or production disk latency; verify those
as operational gates before advancing each production member.
