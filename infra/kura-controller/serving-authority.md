# Positively fenced serving and single-replica recovery

This is the opt-in phase-one boundary of Atlas spec 98. The default is still
`ColocatedLegacy`. Enable the controller's `--serving-authority` and set only a
qualified instance's `spec.servingMode` to `PositiveFenceV1`. The server's
default-off `kura_positive_fence` account flag renders that intent and a manifest
revision suffix. No managed environment enables instances automatically.

## Authority and failure contract

`<instance>-serving` is a durable, resource-version-CAS ConfigMap. Its UID is
pinned on the instance; deletion/recreation cannot reset the epoch. Each grant
binds the instance UID, pod UID, process incarnation and node name. Operators
must qualify node names against distinct physical provider hosts before claiming
host-loss resilience. Required hostname anti-affinity alone does not establish
physical independence for virtual workers.

A separate reconciliation queue renews 15-second grants. The runtime polls with
a one-second request timeout on a dedicated OS thread. It checks wall-clock and
monotonic deadlines with a two-second safety allowance. Admission and metadata
publication are checked separately, including detached blocking commits and
success acknowledgments on existing HTTP/2 and gRPC channels.

There is **no automatic promotion on lease expiry** and no 30-second partition
RTO claim. Arbitrary OS/disk pauses inside publication cannot be proven bounded.
The controller moves to `Fencing` and waits for a `primaryPromotion` request
bound to the previous epoch, pod UID, incarnation and host, plus a positive
external fence receipt. A missing Node, failed probe, deleted API object or
elapsed timeout is not a fence receipt. Only verified cessation of the old
process/host or independent external isolation qualifies. The request must name
the exact replacement pod and incarnation on another host. Crash promotion may
lose acknowledged writes that had not yet replicated; clients must rebuild a
cache miss rather than treating the asynchronous cache as durable storage.

An active primary fsyncs `.kura.primary-unclean` on its data volume. Only a
successful planned revocation removes it. A crashed/expired primary's volume
cannot restart into the peer plane, including after the feature flag is removed.
Quarantine and rebuild it; do not manually erase the marker.

## Planned handover

`plannedHandover` names one destination pod UID and runtime incarnation. The
source rejects new mutations, drains admitted work, and freezes metadata
publication and eviction. The destination must have durably reached the source's
final feed incarnation/head before freezing its retained corpus. Verification
walks the complete retained index in bounded pages, hashes metadata and bodies
with a 64 KiB buffer, and verifies namespace tombstones against that destination.
A bootstrapped state, cursor or consumer count alone cannot satisfy the barrier.
Missing, capacity-skipped, changed or unreadable data fails preparation.

Both nodes fsync the same named receipt. The source then positively acknowledges
revocation while holding the same publication mutex used by public writes.
Only that acknowledgment allows the next epoch. A restarted destination cannot
reuse an old receipt: receipt ownership and the retained-corpus hold are specific
to the live runtime incarnation. An authoritative abort or completed transfer
releases the holds. Preparation has a 300-second deadline; a healthy source is
restored on preparation timeout. A source lost during preparation requires
external fencing. Large corpora may exceed the deadline because this initial
implementation verifies every retained byte; do not increase it casually.

## Recover exactly one ordinal

`replicaRecovery` requires a unique request ID, failed pod name/UID, PVC UID, PV
UID, fenced host and fence evidence. Promote a surviving primary first when the
failed ordinal was the primary. The source must remain healthy, caught up and
on a different host. A restart-safe status journal records the source and target
identities before any deletion.

The controller holds the StatefulSet at `OnDelete`, retains PVCs, marks only the
failed PV `Retain` and `kura.tuist.dev/recovery-quarantine`, deletes only the
recorded claim and pod with UID/resource-version preconditions, then waits for a
new bound claim and a ready, bootstrapped replacement on a third host. The
healthy sibling, its claim and its volume are never reset. Missing-node and
storage-class drift detection only holds rollout for investigation.

One non-expiring namespace-wide Lease serializes all rebuilds, deliberately
stricter than separate source/destination host limits. Controller restart retains
ownership; a failed rebuild does not release its slot or escalate to another
ordinal. Successful verification releases the slot. Investigate interrupted
journals before any manual release. Resize, evacuation and automatic image
replacement are excluded for activated instances.

Quarantined PVs are excluded from the released-volume reaper indefinitely. Keep
them at least 24 hours after replacement verification, investigate stale data,
and obtain an explicit cleanup decision. Removing the quarantine annotation is
not part of automatic recovery.

## Rollout and rollback

1. Apply the additive CRD/controller pair with the authority flag disabled.
2. Upgrade both replicas to the compatible runtime and qualify distinct physical
   hosts, API access, clock behavior, storage and peer routing.
3. Enable authority and the selected instance. Both live runtimes must advertise
   `positive-fence-v1` before the first epoch is granted.
4. Validate public writes/reads, named handover, control-plane loss with persistent
   channels, positive fencing, stale-volume rejoin and interrupted recovery.

Activation sets a sticky rollback-floor annotation and pins the runtime image.
Turning off the account flag does not restore legacy selection. Disabling the
controller flag stops renewal and eventually serving. Keep the capable controller
and runtime pair; an old controller is below the rollback floor. Qualifying a new
runtime image and deliberately updating the pin is an operator procedure while
automatic rolling replacement stays paused.

`/status/rollout.serving_authority` exposes identity, observed grant, deadline,
in-flight mutations, receipt and revocation acknowledgment. The ConfigMap keeps
the epoch, phase, reason and fence evidence. Recovery phases/IDs are in the CR's
status. Inspect these alongside request errors, sync lag and controller errors;
`Fencing` is a required intervention, not a healthy steady state.

## Isolated staging validation

Dispatch `Kura Controller Image` on the candidate branch with
`staging_validation=true`. Its ordinary `server-k8s-staging` deployment identity
adds only the new CRD fields and installs a controller scoped to `kura-spec98`.
It neither replaces the shared controller nor activates production. The install
script is `test/staging/install.sh`. Local human credentials intentionally cannot
create the required RBAC/namespace; never retrieve admin credentials to work
around that boundary.
