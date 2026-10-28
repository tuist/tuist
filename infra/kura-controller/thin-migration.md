# Thin storage handoff

This protocol complements CSI's conservative `ceiling-backed-v1` storage mode.
It does not enable physical overcommit or positive-fence serving. See
[storage qualification](../kura-volumes-csi/thin/validation.md) for the current
rollout decision and measured limits.

## Why connection retirement is insufficient

A Service update changes new connections. An existing connection can still
successfully write to the departing replica, then reconnect to the replacement
before asynchronous replication has copied that write. Staging observed two
fresh-write GET misses after successful PUTs even though the old connection
cohort had retired cleanly. A replication cursor also cannot prove retention:
ordinary backfill may advance past capacity- or age-rejected records.

The controller now persists the source process incarnation, destination pod UID,
destination process incarnation and peer URL before moving an endpoint. The
source checks the peer is a serving member of the same region. Through the
existing kubelet tunnel and end-to-end peer mTLS, the controller requests
`POST /_internal/migration/prepare`. The public router does not expose it.

Preparation checks the source's retained bodies and metadata on that exact
peer, using bounded batches and the existing content verifier. It pins and
checks the source feed to cover writes during the retained walk. It then arms a
write bridge before reporting ready. Every HTTP/gRPC mutation completion while
armed must verify the committed records on the named destination before it can
return success, including mutations admitted before arming. The protocol does
not copy through a new admission path or change eviction policy. Missing data,
lost feed history, an unavailable peer or changed identity fails closed.

Only the ready receipt permits `lvm-rebuild`. Primary selection pins the verified
destination; endpoint observation must name its exact pod UID. The existing peer
handoff, original connection-cohort retirement, donor deletion, replacement
catch-up and OnDelete/template safeguards still apply. This is a planned legacy
cache migration protocol, not a new crash-consistency or global serving grant.

## Bounds, pauses and failures

Preparation has one fixed 20-minute deadline. Verification uses batches of at
most 16 descriptors and existing 64 KiB hashing buffers. Destination verification
is serialized; write acknowledgment waits at most five seconds. An unsuccessful
preparation disarms its bridge and leaves the controller unable to move routing.
Successful preparation cannot expire merely because the controller pauses: its
bridge stays active until the donor drains, retaining its feed pin with one
bounded background verification loop. The loop uses a weak runtime reference
and releases the pin on draining. Ordinary instances do not run this loop.

Pausing source-node enrollment stops new storage moves, but cannot cancel a pod
or claim deletion already issued. Finish observation of that operation before
making changes to its source. Never remove the write binding or blindly restore
routing after `lvm-rebuild`; an armed bridge may already be protecting a moved
endpoint. A destination failure can refuse writes on the old source. Preserve
both volumes and investigate rather than treating readiness or a timeout as a
handover receipt. Changed process identities require fresh qualification.

An armed source pays for replication and destination content verification before
acknowledging writes. The staging pause test deliberately kept routing on that
source: eight concurrent 4 MiB writes delivered only 16–21 MiB/s, with 2.10–3.12 s
p95. Ordinary unarmed serving does not perform these checks. Keep this temporary
cost in the rollout budget, observe write latency during each handoff, and do not
pause a ready bridge indefinitely as a substitute for completing the move. An
unacceptable latency increase should stop selection of further nodes while the
already armed handoff is completed or recovered using its verified identities.

A failed **unarmed preparation** can be retried without restarting the writer:

1. Clear the selected node's `tuist.dev/kura-lvm-migrate` annotation. Retain its
   cordon and verify no deletion has been issued and the source pod has no
   `kura.tuist.dev/lvm-rebuild` annotation.
2. Correct the preparation failure and record the source's current
   `connection_incarnation` and exact target from its
   `kura.tuist.dev/lvm-write-target` annotation.
3. Through the same authenticated peer connection, send
   `POST /_internal/migration/reset` with the same `{incarnation, target}` JSON
   used for preparation. It serializes against acknowledgments and only clears
   a completed failed preparation. A running preparation, ready/armed bridge,
   wrong source process or wrong destination returns conflict. No keys or data
   are deleted. An already empty state is idempotent.
4. After a successful reset, remove only that source pod's write-target
   annotation using a resource-version-guarded update. Recheck identities,
   destination capacity and catch-up, then reselect the source node. This creates
   a new bounded preparation; polling the old attempt never extends its deadline.

An armed handoff has no reset shortcut. Preserve the destination and donor and
complete or explicitly recover the handoff; clearing the bridge would reintroduce
the successful-PUT/missing-GET race.

## Qualification

Keep equal runtime resources and storage sizes in layout comparisons. A
successful handoff test is not a raw-I/O no-regression result. The staging probe
has no application retry loop; Go's transport may retry an idempotent request on
a stale connection. It journals hashes for every successful write, then verifies
the full journal with its expected count against the Service and each replica.
Also verify the pre-seeded corpus, stable PVC identity during template restart,
physical allocation, reserves and unrelated workload identities. Package/runtime
changes require the Linux test gate and another staging qualification before
production enrollment.
