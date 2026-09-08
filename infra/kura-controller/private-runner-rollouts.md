# Private runner-cache process rollouts

`scw-fr-par-runners` runs one private `KuraInstance` per account with two
replicas. Both processes live on the same runner-adjacent Linux host. This
provides overlap for a process deployment; it does not survive losing that host.
`kuraFleet.replicas` counts hosts and remains independent of the instance's two
processes.

## Serving and replication

Runner dispatch continues returning the existing Private Network address and
allocated NodePort. Both the internal Service and the separate NodePort Service
select one primary pod. The NodePort keeps `externalTrafficPolicy: Local` for
source-address NetworkPolicy checks. Required same-instance hostname affinity
keeps both replicas on that address's host, including when there is spare
capacity elsewhere. Kubernetes allows the first pod of a self-affine set to
schedule; see [pod affinity documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/).

Each ordinal has its own `data-<instance>-<ordinal>` PVC, RocksDB store, segment
ring, writer lock, and pod DNS identity. The existing account-scoped mTLS peer
discovery, asynchronous outbox, and backfill walker replicate content between
the two processes and the account's other mesh peers. There is no shared writer
volume or new replication protocol.

## Planned handover

`controllers/private_rollout.go` owns replacement for private instances with
exactly two replicas. Their StatefulSet uses `OnDelete`; Kubernetes readiness
alone cannot advance a rollout. Other instance topologies keep their existing
rollout behavior.

1. Apply the desired template and replica count together with `OnDelete`. The
   controller waits until the StatefulSet has observed that generation and
   published its update revision.
2. Replace the non-primary ordinal first, retaining its PVC. Only one ordinal
   may be absent or terminating at a time. Its serving sibling must report
   Ready, serving, writer-lock ownership, ring visibility, completed initial
   backfill, and an empty outbox before replacement proceeds.
3. Keep traffic on the old primary while the replacement starts and catches up.
   Kubernetes Ready is insufficient: the initial backfill cycle can still be
   pending or degraded after readiness latches. Both replicas must report
   completed backfill, empty outboxes, and matching ring fingerprints (ring
   sizes for runtimes predating fingerprints) before a planned primary switch.
4. Repoint both existing Services to the updated standby. Before deleting the
   old primary, observe ready EndpointSlices containing that exact successor
   pod UID on **both** cache paths, with no other ready target. Allow another
   20 seconds for dataplane propagation. The timer lives on the StatefulSet and
   survives controller restarts; failed health, endpoint regression, changed
   pod UIDs, and new revisions reset it.
5. Delete the former primary normally. Its existing preStop sends `SIGUSR1`,
   then waits 20 seconds before SIGTERM. The process has its existing 240-second
   drain timeout inside a 275-second termination grace period. Its ordinal is
   recreated on the retained PVC with the desired template. The new primary
   remains sticky after rollout.

Failure recovery still uses the normal routability rules. If the serving
process has already failed, the controller may use a routable peer before its
backfill completes. It does not wait indefinitely for perfect cache warmth
while the endpoint is already unavailable.

## Capacity and migration

The region retains **50 GiB per replica**, so each account reserves 100 GiB of
local disk in total. Each pod keeps its own 2 GiB memory request and 4 GiB limit
(4 GiB requested / 8 GiB combined limits), and its own autosized CPU request.
The scheduler reserves each claim through `ephemeral-storage`; the local-path
provisioner enforces the existing per-directory quota. Runtime ring and staging
budgets derive from each claim independently. The 750 Mbps egress annotation
remains per pod; where the shared egress-tree agent runs, both replicas use the
same account class. No new egress floor is reserved. Admission checks require
both replicas to fit on one host.

For existing single-replica installations:

1. Roll out the new **controller first**, leaving the server's region catalog
   unchanged until the old controller process has stopped. An old controller
   does not implement the handover gate, so upgrading the server first cannot
   provide the migration guarantee.
2. Check same-host headroom for the extra 50 GiB claim, 2 GiB memory request,
   and current per-instance CPU request for every account. Include aggregate
   memory limits and system workload headroom when sizing the host. Do not
   shrink the original claim to make room for the standby.
3. Roll out the server catalog change. The private manifest revision includes
   `+replicas2`, so the normal reconciler applies the scale-up to existing CRs
   without creating a new endpoint or server record.
4. Ordinal 0 and its PVC stay in place while ordinal 1 starts on an independent
   claim. If capacity, image startup, peer connectivity, or catch-up blocks
   ordinal 1, ordinal 0 keeps serving and the rollout stays pending. This holds
   even when scale-up and an image/configuration change arrive together.
5. Verify both updated replicas, `status.rolloutHealth`, the selected pod on
   both Services, ready EndpointSlices, and the unchanged node address and
   NodePort before declaring migration complete.

Roll back a runtime image through the same controller with two replicas. Keep
the two-replica catalog and the new controller while rolling back unrelated
server changes; scaling back to one or returning to an older controller gives
up the controlled handover contract.

## Limits and validation

This is process-level serving availability, not synchronous replication or a
guarantee that every concurrent write is readable immediately after handover.
Outbox observations are snapshots, writes can arrive after a sample, and
backfill honors the existing age/capacity horizon. Sustained writes or an
unreachable mesh peer can keep the outbox nonempty and hold a planned rollout;
there is no timeout that forces an unsafe handover. Retained claims and completed
catch-up preserve the warm cache within those limits; eviction, a crash, or
ongoing writes can still produce misses. Persistent connections must honor the
runtime's existing drain/GOAWAY behavior and retry as usual. A drain that exceeds
the finite grace budget can still be terminated.

Host replacement requires a separate overlapping host/endpoint migration.
The automatic node-evacuation path deliberately leaves these NodePort instances
alone: required co-location would strand a replica moved off-host, and changing
the node address would invalidate jobs already using it. Merely retaining a
volume, adding a host, or cordoning the current host does not supply endpoint
overlap.

Focused controller validation: `go test ./...` from `infra/kura-controller`.
`private_rollout_test.go` simulates both replacements, delayed backfill, stale
endpoints, controller restart, stable NodePort addressing, retained independent
PVCs, and a single-replica migration. These are controller tests with a fake
Kubernetes API and runtime reports; they do not measure live Cilium propagation,
drain timing, or artifact bytes. Before promoting, exercise a staging rollout
with continuous uploads and reads against the same NodePort, verify hashes for
preloaded artifacts after each replacement, and repeat with a deliberately
unready/backfilling standby to confirm the primary is retained.
