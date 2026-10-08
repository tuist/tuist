# First production serving-authority pilot

The first target is `kura/kura-tuist-eu-central-1`, the public Tuist EU-West
instance. The historical object name is retained. The Tuist runner cache
`kura-tuist-scw-fr-par` remains legacy: its eligible pool has one physical host.
Do not enable the account-wide `kura_positive_fence` flag for this pilot.
Activate only the selected KuraInstance through its explicit `spec.servingMode`.
This document is an execution procedure, not evidence of completed activation.

## Prerequisites

- Deploy `kuraController.servingAuthority.enabled: true` from the production
  overlay and verify both controller replicas. No instance opts in just because
  this worker is enabled. Once a pilot is active, every later deployment must
  keep the worker enabled: switching it off expires authority.
- Install `../helm/k8s-monitoring/kura-serving-authority-pilot-alert-rules.json`
  through Grafana's alert provisioning API. These rules name only this pilot;
  they do not fire on absent metrics before activation. Confirm the annotated
  controller `/metrics` endpoint is scraped and the rules evaluate successfully.
  Existing replica-availability alerts continue covering loss of all backends.
- Use the ordinary production Pomerium context. A human must grant production
  elevation covering the selected instance, its standby claim/PV, controlled
  pod replacements, planned handover and validation. Agents must not request or
  approve Slack elevation themselves. PV retention/quarantine needs its own
  authorized resource permission; verify it before changing the claim.
- Record fresh instance, pod, StatefulSet, PVC and PV UIDs, resource versions,
  images, original placement, retention policy and current serving primary.
  Store run-specific snapshots and mutation payloads outside the repository.
- Both runtimes must support positive fencing. Confirm both are Ready, have
  completed initial backfill, and have a consistent ring before proceeding.
- Choose a destination and a spare with distinct physical provider identities.
  Check all scheduled workloads' requests, memory-ceiling and egress extended
  resources, free pod slots, disk reservations and actual free bytes on the
  local-path filesystem. Do not use root-filesystem free space as cache capacity.
  Verify clock agreement and private-network reachability in both directions.

## Relocate the standby while retaining legacy serving

Do this before setting `servingMode`. Initial activation withdraws legacy
routing and waits for both authority-enabled runtime incarnations; flipping the
mode first does not migrate colocated disks or automatically restart held pods.

1. Hold the instance's StatefulSet at operator-owned `OnDelete` (without the
   resize hold annotation), with PVC retention on deletion and scaling. Verify
   the controller preserves the hold. Do not change the current primary or its
   claim. Capture its identity again before each destructive standby step.
2. Temporarily constrain the instance's desired node selector to the chosen
   destination hostname, retaining its pool selector. Wait until that placement
   is observed in the held StatefulSet template. Existing pods remain running.
3. Set only the standby's exact old PV to `Retain` and annotate
   `kura.tuist.dev/recovery-quarantine` with the instance UID and migration ID.
   Read both settings back before deleting anything. Retain the PV and bytes;
   do not remove its claimRef or repoint its node affinity.
4. Delete only the captured standby claim and pod with UID/resource-version
   preconditions. Use graceful pod termination, never force deletion on a live
   shared host. Wait for the old process/pod and claim to disappear. If identity
   changes, the primary changes, or the source loses readiness, stop and inspect.
5. Wait for the ordinal to receive a new claim/PV on the selected destination,
   become Ready and finish initial backfill. Verify the original primary pod,
   PVC and PV UIDs did not change. Confirm traffic and replication while the
   replacement catches up.
6. Restore the original pool-wide selector, retaining `OnDelete`. Read the
   template back. The two bound claims now pin the replicas to separate hosts.
   Recheck headroom for rebuilding onto the spare.

Before authority activation, a failed relocation can be investigated with the
original primary still serving. The quarantined copy is retained for recovery;
never delete both copies or clear the primary claim to make scheduling succeed.

## Activate and verify

1. Confirm the authority-enabled controller and pilot alerts are live. Record a
   maintenance window: existing-instance activation is not a zero-downtime
   migration. Verify no other instance has unexpectedly opted in.
2. Patch only this instance to `spec.servingMode: PositiveFenceV1`, with an
   instance UID/resource-version check. Wait for the sticky serving floor, image
   pin, serving ServiceAccount and `Preparing` ConfigMap, and inspect the held
   pod template's authority environment and required hostname anti-affinity.
3. Gracefully replace each legacy pod under the hold, retaining its bound claim.
   Verify the old processes are gone and both replacement runtime reports match
   their current pod UIDs, instance UID, process incarnation and physical hosts.
   Do not manually edit the serving ConfigMap to bypass preparation.
4. Wait for the controller to grant epoch 1 to ordinal 0, with that holder
   reporting valid authority and the sibling reporting invalid authority. Check
   public and stable endpoint readiness and the Service's selected pod.
5. With authorized project credentials, write/read a uniquely named small HTTP
   and gRPC cache fixture and record its digests. Do not disable authentication
   or use the unauthenticated isolated-staging harness against production.
6. Request `plannedHandover` naming the exact destination UID/incarnation. Require
   the matching retained-corpus receipt, positive source revocation, epoch
   advancement, successful reads of the fixture and rejection on old persistent
   sessions. Verify the resulting service route and repeat reads through it.
7. Leave the instance held, the serving worker enabled and the runtime image
   pinned. Record final holder, epoch, pod/PVC/PV identities, endpoint checks,
   alerts and retained volume identity. Monitor errors and replication before
   expanding scope. Keep the old quarantined PV for at least 24 hours and until
   an explicit cleanup decision.

After activation, disabling the account flag, controller worker or authority
settings is not a rollback. Preserve the compatibility floor and live grants.
Automatic image replacement, resizing and evacuation are excluded; future image
changes require explicit qualification and coordinated pin updates.

## Failure validation and expansion

Use isolated staging for deliberate API partitions and process crashes. Do not
power off shared production hosts to validate this pilot. Physical power-off
qualification remains required before broader activation and any host-loss RTO
claim. A real failure uses exact-identity positive fencing, promotion and the
single-replica recovery journal documented in [serving-authority.md](serving-authority.md).

The account-wide flag can replace this per-instance pilot only after every
instance affected by that flag has qualified topology and operational support.
