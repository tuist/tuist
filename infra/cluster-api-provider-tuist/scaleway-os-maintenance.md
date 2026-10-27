# Serialized xcresult host maintenance

Scaleway xcresult hosts accept `tuist.dev/os-update=<version>`, like rack Macs.
The operator performs the in-family update with its existing fleet credentials;
no human needs to extract the key or volume-owner password. A submitted request
survives an operator restart, a disconnected terminal and JIT expiry.

This is an explicit maintenance request, not a scheduled update policy. It does
not adopt Apple's latest release, erase a host, upgrade release families, or
start an update merely because an alert fires. Deployment-triggered approved
version policy is not part of this change.

## Request a wave

First deploy and validate the new server drain protocol and tart-kubelet on
canary. Have two hosts and two Ready processors in the fleet, with its disruption
budget allowing one eviction. A single-host canary needs temporary spare
capacity; the controller will not silently accept an outage. A request for a
runner or builder fleet does not pass the processor checks.

Plan, inspect the named hosts, then submit the same approved target:

```bash
mise run macos-maintenance -- tuist-k8s-canary tuist <processor-fleet> 26.7.2
mise run macos-maintenance -- tuist-k8s-canary tuist <processor-fleet> 26.7.2 --apply
kubectl --context tuist-k8s-canary -n tuist get samm -o json \
  | jq '.items[] | {name: .metadata.name, update: .status.osUpdate}'
```

Use the existing human elevation for the annotation write. The task never asks
for admin credentials, copies Secrets, patches status, or applies RBAC. It sends
intent; the operator owns subsequent work. Cancelling the local command does
not cancel requests already submitted. If a batch submission is interrupted,
inspect which annotations were accepted before requesting the remaining hosts.
After canary acceptance, run the same explicit request against production.

## Safety and progress

The status sequence is `Preparing → Draining → Downloading → Installing →
Converging → Accepting → Succeeded`. Each active phase has a two-hour deadline;
a host waiting for the fleet lock does not consume that deadline until it owns
it. One non-expiring namespaced Lease serializes the fleet, independently of
controller worker concurrency. The holder is the Machine UID, not a recyclable
name. The Lease is deliberately retained after failure or Machine deletion;
expiry must never authorize taking a second host offline.

Before disruption the controller requires a bootstrapped, converged host, a
pinned SSH key, the volume owner's console and secure token, an offered
same-family target, and a Ready processor peer. It waits for the processor
Deployment to settle, then pauses it and waits for that pause to be observed.
Only the configured Deployment can be patched under the operator's existing
namespace-scoped permission. This stops a normal deployment from rolling away
the peer during host maintenance. A Deployment already paused by someone else
is left alone. Explicit administrative scale/delete operations still require
coordination with maintenance.

The Node is cordoned and processor Pods are evicted through the Kubernetes
eviction API. Disruption budgets remain binding. The eviction permission is a
Role in the processor namespace, not a cluster-wide grant. Unknown workloads
block the drain. The host must have no remaining workload Pod objects, including
terminating Pods whose Tart VM finalizer remains, before the download or install
can proceed. Download completion rechecks that condition.

The installer runs `softwareupdate` in the volume owner's console bootstrap
namespace through `launchctl asuser`; the password travels only on stdin. The
operator records the pre-install boot time before launching. It resumes the
same detached job after disconnection and requires both a later boot time and
the requested OS version. Installation clears `hostConfigHash`; after reboot,
the ordinary drift path restores the complete host configuration. A matching
hash, Ready Node and correct console session are required before lifting the
operator's cordon. A pre-existing cordon is preserved. The fleet lock is held
until a processor on that host passes its real dependency/queue readiness
probe, then the owned Deployment pause and remediation hold are removed.

Readiness is not a substitute for an actual parsing acceptance test or the
long-uptime TCP-clock observation. Run those canary checks before approving the
same target in production. This controller does not claim that a new kernel
has passed the approximately 50-day uptime boundary immediately after reboot.

## Processor drain contract

An opted-in Pod has `tuist.dev/graceful-drain: xcresult-v1` and a per-VM writable
`status` share. On deletion tart-kubelet writes its Pod UID to `drain-request`.
The local `Tuist.XcresultDrain` process pauses only its own Oban queue, waits for
`paused: true` and no running jobs, stops the queue and waits for its supervisor
to disappear before atomically acknowledging the same UID in `drain-complete`.
Every processor queue starts paused, including an Oban-only supervisor restart;
the local monitor resumes it only when no drain request exists.
No distributed Erlang or cross-node Oban notification is required.

The host does not accept another Pod's acknowledgement, symlinks or FIFOs.
Reconciliation polls without blocking the host's single Pod worker. The request
survives a kubelet restart. Missing acknowledgement holds the finalizer and VM
even after the nominal grace period; it never silently converts a timeout into
a successful drain. Explicit force deletion with zero grace bypasses the gate
and can interrupt a job. A guest that has already exited can be cleaned up.
So can a VM the running tart-kubelet booted whose guest never passed its
readiness probe (no IP, or every probe failed): `/ready` requires Postgres,
ClickHouse and an unpaused queue, so it has no work to drain, and a release
that crashes on boot would otherwise hold its own replacement forever. A VM
recovered after a tart-kubelet restart has no readiness history and keeps the
gate. This contract also protects ordinary processor rolling deployments after the
Pods have adopted it.

## First rollout and rollback

Keep the PR draft until the real canary operator and processor releases pass:

1. Start a known long-running xcresult job, request Pod deletion, and verify it
   finishes before the VM disappears. Verify the replacement parses a fixture.
2. Restart tart-kubelet during the drain. Verify the same UID request resumes
   and that no new job is fetched after the pause.
3. Request an approved OS update with a spare processor. Verify PDB denial,
   status checkpoints, restored host config, boot/version evidence and final
   processor acceptance. Simulate a concurrent template rollout and confirm it
   remains paused until host recovery.
4. Check TCP timestamps advance and a controlled TIME_WAIT socket expires;
   retain the separate long-uptime observation before declaring the kernel
   defect permanently resolved.

The first transition from old unannotated processor Pods still uses their old
deletion behavior. Arrange that migration during an idle/drained window; do not
claim the new protocol retroactively protects an old guest.

Do not roll back the operator or remove status/schema fields during an active
update. Wait for maintenance to finish, or recover the isolated host first.
Rolling tart-kubelet back removes the drain protection, so finish terminating
Pods before doing so. The server change can be rolled back only after no
opted-in VM is waiting for an acknowledgement; a legacy guest cannot answer it.

## Failure recovery

A failed request retains the cordon, fleet Lease, owned Deployment pause and
CAPI remediation hold. The controller does not start a second installer or
resume host-config pushes after a failure. Removing the request annotation is
not an emergency uncordon. Inspect `.status.osUpdate`, controller events and the
specific host job directory `/Users/Shared/tuist-os-update/<id>/` first.

Only after confirming that no installer is still running and the host is safe
may an operator clear maintenance status and request recovery, or lift the
owned holds. Keep any pre-existing cordon, pause or remediation annotation.
Do not delete the fleet Lease merely to make another host advance: that defeats
the failure boundary. An unexpected failure intentionally requires diagnosis;
the normal successful wave requires no manual SSH, job cancellation or status
patching.

## Proposed deployment trigger (not implemented)

A follow-up can introduce `macosFleet.maintenance.targetVersion`, empty by
default, as an explicit Git-approved target. The operator would submit requests
only for the configured processor fleet, and the deployment cascade would wait
for the entire canary wave plus parsing acceptance before production could
receive the target. It would keep the current one-host lock and all failure
gates. No catalog-following scheduler or unattended major upgrade is proposed.

Adding this trigger requires separate approval because a normal deployment
would then be able to initiate host upgrades. The current diff contains no such
setting or deployment workflow hook; an explicit maintenance request is required.
