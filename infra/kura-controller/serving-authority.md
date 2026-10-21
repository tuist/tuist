# Positively fenced serving and single-replica recovery

This is the opt-in phase-one boundary of Atlas spec 98. The default is still
`ColocatedLegacy`. Enable the controller's `--serving-authority` and set only a
qualified instance's `spec.servingMode` to `PositiveFenceV1`. The server's
default-off `kura_positive_fence` account flag renders that intent and a manifest
revision suffix. No managed environment enables instances automatically. Legacy instances keep
the existing automatic whole-StatefulSet/claim recreation for stale storage,
including colocated host loss; preserving a healthy sibling through explicit
fenced recovery applies only after activation.

## Authority and failure contract

`<instance>-serving` is a durable, resource-version-CAS ConfigMap. Its UID is
pinned on the instance; deletion/recreation cannot reset the epoch. Each grant
binds the instance UID, pod UID, process incarnation and node name. Operators
must qualify node names against distinct physical provider hosts before claiming
host-loss resilience. Required hostname anti-affinity alone does not establish
physical independence for virtual workers.
Measure clock agreement before granting authority. A host outside the bounded
clock allowance must remain fenced; do not extend the grant lifetime to hide an
NTP failure. Inspect `kura.serving_authority.unavailable` for lifetime rejection.

A separate reconciliation queue on every controller replica renews 15-second
grants, independently of leader election. Resource-version compare-and-swap
serializes renewals and transitions, so an old replica cannot overwrite a newer
fencing or promotion decision. The runtime polls with
a one-second request timeout on a dedicated OS thread. It checks wall-clock and
monotonic deadlines with a two-second safety allowance. Admission and metadata
publication are checked separately, including detached blocking commits and
success acknowledgments on existing HTTP/2 and gRPC channels. A missed status
probe or readiness flap leaves a still-valid grant unchanged, without extending
it, during both serving and handover preparation. Renewal resumes only when the
same holder is observed healthy before the two-second safety boundary. Expiry
or an explicit refusal from that holder requires positive fencing. Authority HTTP
errors include bounded cause chains and timeout/connect classification, so a
transport failure is distinguishable from a rejected grant.

A transport-only status observation gap keeps the primary Service's existing route
only while the existing Serving or Quiescing grant remains valid and the live,
Ready, nonterminating pod still matches its holder. The runtime process must
predate the grant renewal, accounting for the two-second clock allowance.
Other configured endpoints reconcile to the same acknowledged holder. This does
not select a new holder, extend authority, or bypass runtime fencing. Interrupted
response-body reads are transport failures, not fresh invalid runtime reports.
HTTP failures, malformed status responses, fresh refusals, changed identities,
expired grants and restarted pods withdraw routing rather than use this fallback.

After an interruption during ordinary serving, a compatible **same live writer**
can acknowledge `fenced_epoch`: it takes the publication mutex, closes admission
and publication, and waits for all admitted mutations to finish. The controller
requires that acknowledgment from the exact current pod, host and incarnation,
with an observed `Fencing` grant and zero mutations, before issuing a new epoch
to that same holder with `resume_epoch` bound to the fenced epoch. The runtime
requires its own in-memory ownership and fencing acknowledgment to accept it.
Old request permits stay invalid. The unclean-volume marker stays on disk; this
does not authorize a restart, a different replica, or an unresponsive process.
If a replacement grant itself expires before delivery, its persisted resume
binding lets the already-fenced original process join publication again and
acknowledge that missed epoch. The controller must still issue another new epoch;
an expired grant is never reopened.
A current operator promotion request takes precedence. Interrupted handovers
continue to require the recovery procedure below.

There is **no automatic promotion on lease expiry** and no 30-second partition
RTO claim. Arbitrary OS/disk pauses inside publication cannot be proven bounded.
Without the live writer acknowledgment above, the controller moves to `Fencing`
and waits for a `primaryPromotion` request
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
Every activated volume also fsyncs `.kura.serving-floor` with its instance UID.
Compatible runtimes reject disabling authority or reusing that volume for another
instance, including on a clean standby. Older binaries do not understand this
floor and remain prohibited after activation.

## Planned handover

`plannedHandover` names one destination pod UID and runtime incarnation. The
controller waits for the source to report the current valid Serving grant before
starting preparation, including after a live-writer resumption.

When the destination advertises `preparation_supported`, the controller first
publishes the named intent while leaving the source in `Serving`. The source
continues accepting reads and writes with normal 15-second lease renewal. The
destination performs bounded retained-index catch-up with normal background
bandwidth admission and no corpus hold. It completes one retained walk; live
eviction does not restart preparation. Requiring an eviction-free pass here can
keep chasing concurrent writes until the preparation deadline. Final Quiescing
repair still repeats on eviction before atomically taking its retained-corpus hold.
The source remains mutable: writes and existing peer-read promotions can cause
normal cache eviction during preparation. The retained-data guarantee covers the
corpus frozen in Quiescing, not every entry present when preparation began.
This phase has its own fixed 20-minute deadline, preserved across reconciliation
and controller restart. Failure, cancellation, changed destination identity or
timeout clears the pending intent without pausing the primary; a new request ID is
required to retry. Source expiry still requires positive fencing.

Only a fresh completion report matching the exact intent, source epoch and both
identities starts `Quiescing` with its original 300-second deadline. Preparation
is not a retained-data receipt: live writes and eviction can change either corpus,
so every existing barrier and revocation check still runs. Older destinations
retain the direct-quiescence path. Upgrade all controller replicas and the clean
standby before requesting this flow; the source may remain on the earlier runtime.

The source then rejects new mutations, drains admitted work, and freezes metadata
publication and eviction. The destination must have durably reached the source's
final feed incarnation/head, then reconcile the source's complete retained index
before freezing its retained corpus. This bounded replication pass fetches missing
records outside the normal bootstrap horizon without echoing them into the sibling
feed. It preserves resource admission, store capacity, version and tombstone checks;
an incompatible or undersized destination can still fail the final barrier.
Named repair bypasses the recency cutoff at listing and dispatch: an older
missing record still belongs to the source's retained corpus. Ordinary catch-up
keeps its recency policy. Repair does not increase ring capacity or bypass disk
admission. If rotation evicts records during a repair pass, the destination walks
the retained index again before taking its hold; this also repairs action-cache
entries cascaded away by blob eviction after an earlier presence check. A pass
without eviction acquires the hold atomically with its eviction-generation check.
All Quiescing repair passes share its original 300-second deadline. Equal-sized fragmented
replicas are not guaranteed to converge; the final full-corpus check still
refuses promotion when required data remains missing.
Only one repair runs per destination, and an abort, changed intent or deadline
cancels it. A retry after the destination is frozen does not repair or release
that hold. Older destinations keep their verify-only behavior. Verification
walks the complete retained index in bounded pages, hashes metadata and bodies
with a 64 KiB buffer, and verifies namespace tombstones against that destination.
A bootstrapped state, cursor or consumer count alone cannot satisfy the barrier.
Missing, capacity-skipped, changed or unreadable data fails retained-corpus verification.
Compatible destinations advertise bounded batch verification on the initial
response. The source sends at most 32 record descriptors, 64 KiB of descriptor
JSON and 8 MiB of referenced bodies per batch (a single larger record travels
alone). Both peers still hash every byte sequentially with the same buffer and
ordered receipt digest. This removes per-record network round trips without
adding parallel readers. Older destinations use the individual-record path;
older sources remain supported. Rejections name the failing record within a
batch, and a partial batch acknowledgment cannot complete verification.

Both nodes fsync the same named receipt. The source then positively acknowledges
revocation while holding the same publication mutex used by public writes.
Only that acknowledgment allows the next epoch. A restarted destination cannot
reuse an old receipt: receipt ownership and the retained-corpus hold are specific
to the live runtime incarnation. An authoritative abort or completed transfer
releases the holds. Quiescing has a 300-second deadline; a healthy source is
restored on verification timeout. A source lost during Quiescing requires
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
storage-class drift detection only holds rollout for investigation on activated
instances (including instances with a sticky rollback floor).

If PodGC has removed the failed pod, recovery accepts its absence or an
unscheduled Pending replacement owned by the same StatefulSet and mounting the
declared claim. The original PVC/PV/host identities must still match. The journal
keeps the original fenced pod UID and separately records the exact replacement
UID before deletion, including replacements created while recovery is running.
A scheduled replacement or different claim/owner is rejected.

Validation and journal persistence precede acquisition of the rebuild slot, so
invalid requests do not block corrected requests with new IDs. An in-flight
journal remains immutable; withdrawing it does not authorize another rebuild.

One non-expiring namespace-wide Lease serializes all rebuilds, deliberately
stricter than separate source/destination host limits. Controller restart retains
ownership; a failed rebuild does not release its slot or escalate to another
ordinal. Successful verification releases the slot. Investigate interrupted
journals before any manual release. Resize, evacuation and automatic image
replacement are excluded for activated instances.
Placement changes are reconciled during rebuilding. Only a replacement that is
still unscheduled and has an obsolete node selector is recreated; its new claim
is retained and the serving sibling is untouched.

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
automatic rolling replacement stays paused. A newer requested image does not
stop ordinary workload reconciliation: the template remains at the qualified
runtime pin and the instance reports Pending with the held-image reason. The
requested image remains unchanged, and only an explicitly updated pin permits
the template to adopt it. OnDelete and volume retention remain in force.
For an already activated instance, replace the clean standby first, then perform
a named handover before replacing the positively revoked old primary. Do not
restart an active primary onto its marked volume. The first handover from an old
source still uses individual-record verification; batching applies after the
source supports negotiation too. Keep `OnDelete` and the explicit image pin
through this procedure.

While the requested image waits on this procedure, `status.imageHold` reads
`FencedImagePin` (the pin differs from the requested image) or
`FencedReplacement` (the template carries the qualified image and old-revision
pods remain). The control plane's progressive rollout leaves a held server out
of wave convergence instead of pausing the fleet at the wave deadline, so a
fenced instance never blocks other accounts. It does not soak the target on
the held instance: the operator procedure is that instance's qualification,
and once both pods run the requested image the server rejoins convergence and
the health gate. A canary wave made only of held servers still pauses.

`/status/rollout.serving_authority` exposes identity, observed grant, deadline,
in-flight mutations, receipt and revocation acknowledgment. The ConfigMap keeps
the epoch, phase, reason and fence evidence. Recovery phases/IDs are in the CR's
status. Inspect these alongside request errors, sync lag and controller errors;
`Fencing` is unavailable until the live writer handshake completes or an operator
supplies external fence evidence; a persistent `Fencing` state requires intervention.
Controller metrics expose phase gauges and the latest valid-holder observation.
`serving-authority-alerts.yaml` supplies example rules for fencing, an
unacknowledged holder and a stalled rebuild; install them in the environment's
alerting system before activation. They are not installed by the staging fixture.
The workload controller uses 5/3/1-second leader lease/renew/retry timings and
releases leadership after graceful shutdown. Authority reconciliation runs on
all replicas because unrelated workers can keep that lease while draining after
grant renewal has stopped. A surviving replica can continue renewing during
that interval. Loss of all authority reconcilers still expires grants and
requires positive fencing. Run at least two controller replicas for rollout
continuity; a single replica cannot renew grants while its only process restarts.
Upgrade runtime and controller in either order: old runtimes cannot acknowledge live-writer fencing,
and old controllers ignore that additive report. Recovery becomes automatic only
when both support it; rollback to either old component leaves an expired writer
closed and needing the original external recovery procedure.

## Isolated staging validation

Provision an isolated namespace, a namespace-scoped authority-enabled controller,
and a two-replica `PositiveFenceV1` instance through an authorized staging
deployment. Pin the candidate images and qualify distinct physical hosts and
clock agreement before running faults. The image-build workflow has no isolated
deployment job. Local human credentials intentionally cannot create the required
RBAC/namespace; never retrieve admin credentials to work around that boundary.

The partition policy fixture is
`kura/test/e2e/serving-authority/api-partition.yaml`. It targets only pods carrying
`spec98.tuist.dev/api-partition=true` in the isolated `kura-spec98` namespace.
Install it through the authorized deployment identity before the partition case;
if the fixture namespace is overridden, render the policy into that namespace
too. The client removes the fault label when the case exits.

The opt-in ShellSpec harness in `kura/spec/e2e/serving_authority_spec.sh`
exercises existing HTTP/2 and gRPC sessions. Its partition mode verifies refusal
while API access is denied. `KURA_E2E_AUTHORITY_MODE=api-recovery` also waits for
the live-writer handshake after removing the fault, checks the unchanged
incarnation and new epoch, and proves the rejected upload remains absent.
Without a compatible runtime/controller pair, the old primary remains fenced:
positively stop it, promote the exact survivor and rebuild the quarantined ordinal.
Cilium policy propagation is asynchronous;
the test waits for observed expiry and sustained rejection rather than treating
the label write as proof of a partition. Keep physical host power-off tests on
dedicated hosts; process termination on shared staging hosts does not qualify
physical host-loss recovery.

Set `KURA_SPEC98_CONTEXT` explicitly. `KURA_SPEC98_INSTANCE` and
`KURA_SPEC98_NAMESPACE` select a fresh fixture without changing the default
`kura-spec98` names. After a successful partition case, preserve its reported
`lateHash`/`lateSize`; pass them as `KURA_E2E_MISSING_HASH` and
`KURA_E2E_MISSING_SIZE` to the next handover case after positive fencing and
rebuild. It requires ByteStream `NOT_FOUND` on the promoted primary before
starting another handover, verifying that the rejected late write did not appear.

Set `KURA_E2E_AUTHORITY_MODE=leader-restart` to restart the isolated controller
while continuously checking HTTP writes, gRPC capabilities, and the unchanged
valid primary epoch. This mode requires both replica endpoints and intentionally
targets only `spec98-tuist-kura-controller` in the selected fixture namespace.
