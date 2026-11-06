# Safe Linux host kernel remediation

Status: draft design. No controller, workflow, installer or admission changes are
implemented by this document. Merging this document does not patch or reboot a
host. A merge-to-remediate implementation must satisfy the gates below before it
is enabled. Do not interpret this proposal as proof of remediation or recovery.

## Outcome and availability contract

Patch existing affected Linux hosts in controlled waves and prevent newly
provisioned or rebooted hosts from accepting untrusted guests on an unapproved
kernel. This is protection against the identified vulnerability, not unknown
future vulnerabilities or a host that has already been compromised.

For the first rollout, "without disruption" means no interrupted admitted CI job,
sandbox turn or REAPI execution, no lost acknowledged workload data, and enough
verified healthy capacity to keep the service available while one host is out.
It does not promise unchanged queue latency, transparent live migration, or that
a resident sandbox never pauses or reconnects. If those stronger guarantees are
required, do not activate until the necessary migration/redundancy is proven.

Spare capacity is a precondition, not an optimization. A singleton without a
qualified replacement blocks the wave. A timeout stops and alerts; it never
authorizes force-draining, data loss or a wider availability budget.

## Scope and evidence

The earlier production inspection found ten Ubuntu Linux runner hosts on
6.8.0-138, -139 and -147. They also run Firecracker sandboxes and REAPI workers.
These are the first priority, not the complete Linux inventory. Reconcile CAPI,
Kubernetes, rack and provider inventory, including spare, parked, offline and
adopting hosts. Classify each as fixed, vulnerable, unverified or documented not
affected. Unknown evidence must never count as fixed. macOS is outside this CVE.

The identified issue is CVE-2026-99999 in the host IPv4 checksum path. Guest or
Firecracker upgrades alone do not repair it. Verified upstream patch:
[6785011f8b16](https://github.com/torvalds/linux/commit/6785011f8b16abf40b1e9d8b2e332232b3e68822).
Ubuntu's Noble GA candidate is image/modules/modules-extra 6.8.0-149.149,
running release 6.8.0-149-generic. The
[exact Ubuntu changelog](https://changelogs.ubuntu.com/changelogs/pool/main/l/linux/linux_6.8.0-149.149/changelog)
and [release source](https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble/tree/?h=Ubuntu-6.8.0-149.149)
contain the guard and its five consumers. Launchpad source publication
[18924924](https://api.launchpad.net/1.0/ubuntu/+archive/primary/+sourcepub/18924924)
reports Published in Updates, newer than the vendor CVE page's work-in-progress
status. Retain both facts rather than silently replacing the vendor status.

The local test authenticated Ubuntu archive metadata and image/modules packages,
then booted the kernel directly in QEMU TCG, loaded e1000, pinged its gateway and
powered off successfully. It did not exercise disk boot, GRUB, package hooks,
Secure Boot, KVM or physical recovery. The staging APT check was a simulation,
not an installation. No hosts have been patched by this investigation.

Other kernel flavours/distributions need their own vendor evidence and approved
upgrade path. Never compare upstream version numbers to vendor-backported
kernels or send an Ubuntu APT operation to an immutable/Talos host.

## Policy and ownership

Keep a versioned managed-host policy in Git, rendered through managed Helm
configuration and off by default for self-hosters. Identify OS, release,
architecture and kernel stream, with explicit qualified source/package/build
versions and authenticated repository provenance. Begin with exact builds;
qualify later ones explicitly. Missing or unsupported identities fail closed.
The desired target is distinct from installed packages, the running build and
workload acceptance. Installing packages is not remediation until rebooted.

Add persistent maintenance orchestration to the existing CAPI provider, using
its provider-owned executors and credential boundaries. Do not put fleet SSH
keys or provider credentials in GitHub Actions or human/orb sessions. A rollout
resource records an immutable policy revision, explicit UID-bound membership,
wave order, operation IDs, per-host phase and evidence, and which holds it owns.
Generate CRDs/deepcopy output through the provider's existing generation task.

One non-expiring environment-wide maintenance Lease initially permits at most
one unavailable host across fleets/rollouts. Also require workload-specific
quorum and regional serving capacity. A CI cancellation, operator restart,
expired observation, deleted rollout or uncertain host response must not free
the lock and authorize another reboot. Count already unavailable hosts before
acquiring it: one operation is not necessarily one unavailable host. Keep the
lock independent of rollout garbage collection, with finalizers retaining
ownership until safe resolution. Deletion/reinstall, remediation, disruptive
converge and substrate deployments must participate in the same protection;
serializing only the new reconciler is insufficient. An explicit recovery
decision is required to abandon a failed host.

Maintain a durable active-host slot separately from environment Lease ownership
so two reconciles of the same rollout cannot start different hosts. Revalidate
availability under the acquired lock and immediately before withdrawing serving
capacity. Count unavailable, quarantined and maintenance-held hosts plus pending
capacity commitments. Unknown inventory or health blocks progress.

## Per-host transaction

1. **Plan:** verify host/Machine/Node identity, exact packages, required drivers,
   boot space, disk/RAID health, workload ownership, spare serving capacity and
   an independent console/rescue path. Record the previous kernel and BootID.
2. **Hold:** acquire the maintenance lock and hold destructive remediation and
   conflicting deployments. Record existing cordons/holds. Close all CI,
   sandbox and REAPI admission, including already-running daemons, and wait for
   acknowledgement. Do not rely on cordon or grant expiry alone.
3. **Drain:** retire idle runners, let claimed jobs/turns/executions finish, and
   inspect every namespace plus DaemonSets/static pods and node-local PVs.
   Unknown workloads, in-flight operations or unacknowledged holds block.
   Missing Nodes, terminating Pods and lost connections are not empty-host
   evidence. Confirm host-local guest/process teardown, not just Pod absence.
4. **Recoverable:** with admission still closed, require guest disk-sync success
   and a final verified off-host recovery copy. Ordinary pause does not request
   sync; even requested sync may fail while pause succeeds. Require
   `sync_disks:true` and `disks_synced:true`, not just successful pause/archive.
   Stateful services require an application-consistent equivalent and a
   demonstrated restore path. On-disk snapshots and early live copies do not
   meet this gate. Define a separate non-destructive maintenance backup: normal
   archival clears bindings and deletes the local jail. Retain local originals,
   bind the recovery copy to the post-hold workload generation, verify completed
   object identity/checksum and restoration, and specify whether recovery
   restores memory/processes or cold-boots disks. Preserve the old kernel,
   initramfs, modules and boot config.
   Inventory retained disk snapshots and their catalog too. For an already
   paused, unsynced sandbox, permit only an authenticated maintenance sync/resume
   exception under the hold, with no customer execution, turn or REAPI assignment.
   Restore its original paused state and retain originals and recovery copies
   through acceptance/recovery. If safe sync or restore cannot be established,
   block rather than silently accept crash-consistent recovery.
5. **Install:** install the exact authenticated package set without automatic
   reboot, respecting package locks. Explicitly control package hooks and
   service restarts; reject unqualified dependency changes. Validate initramfs,
   boot entries, drivers, DKMS and Secure Boot where applicable.
6. **Reboot:** persist the reboot intent and pre-boot evidence before executing.
   A durable host-side operation marker must distinguish not-started, running
   and completed. After ambiguous transport failure, inspect rather than issue
   another reboot. Keep admission/remediation holds throughout.
7. **Verify:** require changed BootID, approved running build/package evidence,
   healthy storage, kubelet/containerd/Cilium, KVM/nested virtualization, guest
   networking/DNS, private-cache connectivity and public egress identity.
8. **Accept:** permit only authenticated maintenance probes. Run a real CI/cache
   round trip, sandbox known-data pause/resume and REAPI execution where used.
   Bind evidence to policy, host UID and BootID. General work remains closed.
9. **Complete:** after the wave's healthy observation window, recheck current
   boot and policy, restore only owned scheduling/admission/remediation state,
   then release the lock. Preserve pre-existing holds and cordons.

Failure stops the rollout and retains the relevant lock/holds. Proposed bounds
are two hours for drain/install and thirty minutes for host return, subject to
staging qualification. They are stop-and-alert deadlines, never force-progress
deadlines. Monitoring unavailable or stale means do not advance.

Before each host effect, persist phase intent, operation/attempt ID and immutable
policy/package digest. Bind commands to expected host identity and pre-boot ID.
Use a durable host-side job/journal with started/running/exited/unknown outcomes,
a host operation lock and fenced attempts for installation, boot configuration
and reboot. After controller restart or transport uncertainty, inspect that job
and package state instead of blindly rerunning it. Recovery and unlock reconcile
its journal, current boot identity and every owned hold.

## Admission and future hosts

The existing join script starts kubelet without a kernel-compliance gate and
`joinedGuard` skips a successful join on subsequent reconciles. Bootstrap edits
alone cannot patch existing hosts. Add always-reconciled kernel verification
outside that first-join shortcut.

Update supported base images/installers, but do not trust an OS family name such
as `ubuntu_24.04`. Register new hosts quarantined from their first registration,
without a compliance label. Trusted networking, repair and verifier agents may
run; general guest admission must not. Install/reboot/verify the approved kernel
before releasing only the owned quarantine.

A controller-issued proof must bind policy revision, host/Node UID, running
build and current BootID. Read through pinned SSH or an authenticated host agent,
not a guest. Require an existing host-key pin, not first-use trust during
maintenance. Authentication assumes trusted privileged host software; it is not
attestation of an uncompromised host. A protected NodeRestriction label is useful
only after confirming the cluster enforces that restriction. Never configure
kubelet to self-assert it through rack node labels. Reconcile proof freshness
and invalidate it before planned reboot and on boot/policy change.

Labels survive reboot, and `--register-with-taints` is not reapplied to an
existing Node. Therefore also install root-owned local launch interlocks on
Kata/QEMU and Firecracker/REAPI entry points. They must reject stale/absent proof
for the actual boot/kernel and approved policy on every launch/resume, including
template prebuilds, even before the control plane notices a restart. Do not
disable all containerd/kubelet service startup: trusted diagnostics must remain
available. Installing an interlock must not kill existing work.

Integrate all of these paths before enabling maintenance:

- Runner capacity, reservation, idle/claimed dispatch and Pod placement. A
  scheduler selector alone cannot fence an already-polling warm runner.
- Sandbox allocation, placement, resize, resume, new residency/turn and idle
  execution. Persist a hold under the same node lock as grant publication, so
  stale observations cannot reopen admission. Grant expiry does not terminate
  an existing residency or prove all in-flight work is finished.
- Every REAPI worker/admission and execution-start path, not just the standard
  sandbox daemon, including warm-VM assignment and direct claims on fixed,
  non-elastic nodes. Require explicit drain acknowledgement from the worker.

The persistent hold is independent of expiring capacity grants and keyed by
environment, physical host/Machine/Node identity and operation generation.
Ordinary capacity publication cannot clear it, including after restarts. Define
the admission linearization point under the shared node lock: previously
admitted work finishes; later claims queue or fail retryably. Carry the fencing
generation through outstanding creates, warm assignments and direct execution.
The generation changes monotonically. Reservations and outstanding commands
issued before the barrier must be recorded in the drain set until settled, or
rejected/cancelled before starting. Acknowledgments bind host incarnation and
fence generation. Reconnects cannot clear the hold. Final backup/reboot waits
for all grandfathered commands and claims, not merely a quiet status report.

Do not remove the sandbox DaemonSet's scheduling eligibility or roll it as a
drain mechanism: it must remain available for disk sync, archival and recovery.
Use workload-admission fencing and preserve its existing local state.

On existing hosts, start verification in observation mode without fake safe
labels or reboots. Prepare patched spare capacity before enforcing placement.
Existing vulnerable hosts are temporary, tracked exposure with an agreed
deadline, not permanently grandfathered compliance. Closing that exposure
immediately may reduce capacity; do not claim otherwise. Failed proof refresh
denies new admission, but does not kill an active job solely for a control-plane
outage. Suspected compromise follows incident response, not compliance checks.

## Waves and merge activation

| Wave | Scope | Exit gate |
| --- | --- | --- |
| 0 | Staging representative of every supported hardware/kernel/boot/storage class | Physical boot, workload acceptance and independent recovery drill; qualified spare capacity |
| 1 | Canary hosts, sequentially | Full workload checks and at least 30 continuous healthy minutes |
| 2 | One representative production host | Explicit production activation approval, full checks and at least 60 healthy minutes |
| 3+ | Remaining nine runners after the sentinel, initially 2 / 3 / 4 | Still one unavailable host at a time; at least 30 healthy minutes between batches |
| Role-specific | Other affected hosts grouped by region/storage/failure domain | Qualify their upgrade path first; preserve serving replicas and database/control-plane quorum |

Batch sizes and observation windows are proposed defaults, not measured results.
Freeze membership only after fresh inventory. Unknown or offline hosts remain
outstanding until verified, and returning spares remain quarantined.
The sentinel is included in the observed ten. Batches are observation/promotion
groups, not parallel unavailable-host allowances.

The eventual main workflow publishes an approved policy and submits/watches
persistent rollout intent. It carries no host credentials and performs no SSH
package operations. Serialize it and do not cancel in-flight maintenance for a
new push. Retrying CI reads status instead of duplicating side effects. Ordinary
application deploys and the hotfix shortcut cannot bypass maintenance gates.
Deploy/scale/remediation actors must honor the same hold; workflow concurrency
alone does not serialize provider-initiated or other workflow actions.

The existing application cascade is not this qualification chain: it can deploy
canary without staging and bypass canary on hotfixes. Require a separate,
non-bypassable staging/canary/sentinel evidence chain, pinned to rollout UID,
policy digest, physical host/Node UID and post-reboot BootID. Probes need a narrow
authenticated exception while general dispatch stays closed; fleet-wide probes
on untouched hosts and briefly reopening admission are insufficient.

Enable only after staging recovery, all admission paths and spare capacity have
been qualified. Initially require environment promotion and production approval;
subsequent approved policy merges can progress automatically under those same
verified gates. A merge never grants an agent human JIT elevation.

## Recovery and current blockers

The observed staging host has RAID `/boot`; `grub-reboot` must not be treated as
a proven automatic fallback. Old-kernel retention cannot reset a hung machine.
Qualify independent console/rescue, boot selection and old-kernel recovery on
staging using disposable known data, then reapply/requalify the fixed kernel.
Recovery to a vulnerable kernel keeps untrusted admission closed. Never delete
a CAPI Machine for rollback: OVH release reinstalls the host and wipes data.
Record per-host recovery capability and its human operator. Qualification must
exercise failed early boot, wrong kernel, unreachable network and interrupted
installation, with old-kernel recovery that preserves `/data`.

The read-only staging recheck on 6 November 2026 still found one `runners-linux`
host, running 6.8.0-147-generic. Its node-local Kura rehearsal has
`recovery-rollout-hold=true`, two desired replicas and only one Ready. This is a
current blocker, not a permanent inventory declaration. Recovery access remains
unverified. Do not interrupt the rehearsal or silently accept a singleton outage.

## Validation required before activation

1. Offline tests for vendor/stream matching, unsupported builds, absent evidence,
   stale proof, changed BootID and old-image reuse. No generic version shortcut.
2. Tests for hold-versus-grant/dispatch races, polling warm runners, existing
   residencies, REAPI starts, failed guest sync and unknown local-state workloads.
3. Fault injection at every persistent side-effect boundary: controller restart,
   API/SSH timeout, completed install with lost response, ambiguous reboot and
   cancelled workflow. The next host must remain untouched after failure.
4. Full-disk disposable VM tests for authenticated installation/hooks, initramfs,
   GRUB and preserved-kernel recovery. Direct-kernel QEMU boot is insufficient.
5. Physical staging boot/recovery and capacity proof; then canary and sentinel
   acceptance. Persist sanitized commands/manifests, timestamps, exit statuses,
   workload results and cleanup verification as they execute.
6. Final inventory accounting and continuous alerts for vulnerable-running,
   pending reboot, unverified/offline capacity and stalled/failed waves. Update
   `server/data-export.md` if implementation adds stored customer-related state.

Ship in this order: observation and inventory; dormant new-host/current-boot
enforcement plus all admission paths; persistent maintenance and intent workflow;
local recovery qualification; physical staging/canary; production activation.
Shipping enforcement code is not activating it. Existing hosts remain
observe-only until spare capacity, recovery and maintenance are qualified. No
merge may deny their launches or require new selectors merely because proof
labels are absent. New-host quarantine may activate separately only after its
bootstrap-to-verification path is qualified. Each environment activation needs
an explicit checklist for those prerequisites and an owned-state rollback that
never falsely labels vulnerable hosts compliant.
No partial implementation may describe the fleet as patched or the rollout as
disruption-free.

## Adversarial review disposition

The read-only source review identified seven activation blockers: execution
drain is broader than scheduler drain; capacity grants are not persistent
maintenance holds; all destructive lifecycle paths must share the interlock;
physical recovery is unqualified; normal archival is not a maintenance backup;
future-host enforcement needs a per-boot launch gate; and the application deploy
cascade is not a staging-first kernel qualification chain. The requirements
above address each in the design, not in executable code. All remain open
implementation/qualification gates.

The first implementation merge may publish policy, read-only inventory and
observe-only preflight/status. It must report unmet prerequisites as **Blocked**,
not successful remediation. It must not cordon hosts, change required selectors,
install packages, reboot, or activate new-host quarantine before its bootstrap
and recovery route is qualified. This document itself activates none of these.
