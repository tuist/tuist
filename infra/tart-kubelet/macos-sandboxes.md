# macOS sandbox operation

macOS sandboxes use the existing account API and Managed Agents session router.
The `macos_sandboxes` account feature flag is **off by default**, in addition to
the existing `sandboxes` gate. Select `platform: "darwin"` when creating a sandbox
or agent environment. Defaults are template `macos`, 8 vCPU, 8 GiB RAM and a
10 GB workspace. The other native shapes are 8 vCPU with 16 or 24 GiB RAM.
The workspace is `/Users/runner/work`; Linux requests retain their existing defaults.

## Deployment and enablement

Deploy all of the following before enabling an account:

1. The additive server migration and server release. Existing rows remain Linux;
   the new columns record platform, Node UID and resident capacity ownership.
2. The updated runners-controller, kubelet and chart. Managed values prepare
   the host service; self-hosted values leave `sandboxes.macos.enabled` off.
   Only kubelets advertising `tuist.dev/macos-sandbox-host=v1` receive control
   Pods, preventing an older kubelet from booting a control Pod as a CI VM.
3. A **new runner image containing the `TUIST_SANDBOX` boot guard** from this
   change. An older image can halt when it finds no CI dispatch token. The chart
   uses the configured, versioned Xcode 26.6 runner image by default;
   `sandboxes.macos.image` can pin an explicit compatible digest.
4. Wait for the `tuist-macos-sandboxd` control Pod to become Ready, its host to
   appear in sandbox node presence with the `macos` template, and a fresh
   `tuist.dev/macos-sandbox-grant` Node annotation. Preparation compiles the
   isolated runtime once and downloads the base image at background priority.
5. Run the acceptance checks below on staging, then enable `macos_sandboxes`
   for the intended account through the existing feature-flag administration.
   Create with `{"platform":"darwin"}`, execute a command, pause, resume and delete.

Enabling the feature flag does not provision new hardware. No available grant
means no placement. Disabling it stops new native creation, resumes, commands and
Managed Agents admission. Pause, stop-worker and delete remain available.

## Capacity and CI priority

The server reserves native CPU, RAM and one VM slot in a PostgreSQL transaction
under a per-node advisory lock. It binds ownership to the Kubernetes Node UID;
reusing a node name cannot move a checkpoint to a replacement machine.

The CI allocator publishes grants only with known, unqueued CI demand and a
healthy, unreserved host. Grants expire after 15 seconds and are also bound to
the current control Pod UID. Unknown or stale demand denies new native work.
Each grant specifies CPU, RAM and VM slots remaining after non-reclaimable CI
reservations. Placement subtracts existing native reservations from that allowance,
so a host occupied by CI is not selected just because its queue is empty.
The kubelet refreshes host memory and process pressure on each heartbeat. macOS
memory warning/critical levels and a process table at least 90% full report
pressure; failed probes report `Unknown` and deny native admission. This also
recovers conditions left `Unknown` by Kubernetes after a kubelet heartbeat gap.
Idle warm CI runners can yield to a pending sandbox reservation; active CI jobs
are never selected for this preemption.

Every native VM also owns a resource-requesting execution Pod. The host serializes
final native and CI launches under one gate and rereads bound Pending, Running
and Terminating Pods, enforcing CPU, RAM and Apple's two-VM limit. A resident
pause retains the full Pod charge. The host repairs missing reservation Pods
from its journals before CI launches; uncertain ownership fails closed.

The background controller checkpoints idle residents when CI revokes admission,
or after the bounded 30-second idle grace. Ownership reconciliation and eviction
run independently of image downloads and control connection preparation, so a
failed or slow image update cannot delay returning idle capacity to CI.
It does not interrupt an active managed
worker or exec command. CI may therefore wait for active native work to finish
and for the checkpoint to complete. A failed checkpoint or process fence retains
its reservation. No capacity is released merely because a save was requested.

The isolated disk budget counts complete writable root disks and two memory
images per environment, including evicted environments, against half the host
filesystem. Save/restore admission also leaves 20 GiB free beyond two memory
images. A cold template pull requires 100 GiB beyond the CI preparation floor
of 30% free disk. These are conservative admission checks on a shared filesystem,
not a dedicated host filesystem quota. Guest workspaces have an APFS quota;
root disks retain the image's fixed logical ceiling. Automatic Tart pruning is
turned off in the isolated store so it cannot decide environment retention.

## Runtime, identity and recovery

The host service lives inside tart-kubelet. The control Pod supplies declarative
configuration and a revocable Pod-bound identity, not a VM. Tokens are minted
for audience `tuist-sandboxes` on each connection. The server verifies the current
Node and control Pod UIDs before accepting native presence. Session commands
carry the stored Node UID. Credentials travel through the authenticated socket
and guest bridge stdin; they are not written into host journals or argv.

The private store is `/var/lib/tart-userdata/.macos-sandboxes/`:

- `records/<id>.json`: fsynced intent, ownership, shape, pinned runtime/tools,
  runtime instance nonce and current/finished worker identity.
- `tart/vms/sbx-<UUID>/`: writable disks, runtime control files and checkpoint.
- `runtimes/` and `guest-tools/`: immutable versions retained for older guests.
- `config.json`: last valid configuration, permitting ownership recovery and
  idle eviction even when the control Pod has been removed.

VM names contain the full UUID and are unique across Tart stores. The service
holds an exclusive host lock and never launches an unjournaled VM. On restart it
reconciles process identity or checkpoint proof before making capacity available.
Native runtime stdout/stderr use regular files, so loss of the kubelet does not
break a live VM’s output pipes. A missing process without a valid checkpoint is
an error; it never silently cold boots a replacement. An interrupted initial creation requires explicit deletion
and retry. Unknown VMs or journals from another Node incarnation require operator
reconciliation and keep CI admission closed on that host.

Resident pause/resume uses Apple Virtualization in a private Tart 2.41.1 build,
pinned to commit `543453404cd1b15c1338b6b70e162d000c8ba5e2`. It does not replace the
fleet's CI Tart binary. Eviction saves a checkpoint, fsyncs it with an instance
marker, then asks that same paused process to exit. The host verifies exit and
suspended state before releasing its Pod. Both resident and evicted resume
invalidate previous checkpoint proof before the guest can modify disk again.

Guest execs and managed workers retain completion proof. Process groups are
terminated and reaped at completion or timeout. Uncertain completion remains
busy. A durable finished work ID in reports recovers a missed exit event without
ending a newer turn. Snapshots stay coupled to this host, its Apple runtime,
disks, devices and pinned tool paths; this is not migration or host-loss recovery.

Deletion journals its intent, fences the process, removes the VM, environment
share and log, then removes the reservation and fsyncs journal deletion. Interrupted
deletes retry after restart. The existing server 14-day cleanup applies; orphan
VMs are deleted on reconnect when their server row no longer exists. Runtime/tool
versions and template caches are deliberately retained for compatibility; reclaim
those only after verifying no journal or checkpoint references them.

## Acceptance and rollback

Automated coverage lives in `internal/macosandbox`, the guest bridge tests,
CI allocator tests, and server sandbox/API tests. `TestNativeControlPlaneAcceptance`
uses the real WebSocket client, dispatcher, journal and Kubernetes adapter with a
fake Kubernetes client and VM runtime. It covers pause/resume, restart, CI revocation,
worker completion, eviction, restore, reconnect token renewal and deletion.

`TestAppleRuntimeAcceptance` additionally boots a real VM on an **already reserved
Mac**, holds a random nonce only in a guest process's memory, and verifies it after
resident resume, host-service recovery and eviction/restore. It logs time through
the first guest command. Build guest tools with `go generate ./internal/macosandbox`
before building/running the kubelet locally; the release Dockerfile embeds them.
On a dedicated staging Mac, from `infra/tart-kubelet`:

```sh
TUIST_MACOS_E2E_RESERVED_HOST="$(hostname)" \
TUIST_MACOS_E2E_ROOT=/Users/tuist/macos-sandbox-acceptance \
TUIST_MACOS_E2E_IMAGE='<versioned sandbox-capable runner image>' \
go test -v -timeout 35m ./internal/macosandbox -run '^TestAppleRuntimeAcceptance$'
```

Reserve capacity through the normal staging procedure first, let CI drain, and
release that reservation after verifying cleanup. The test never acquires fleet
capacity itself. Also validate the deployed account API and authenticated native
node connection; the in-process protocol test does not replace this live check.

For rollback, disable account admission first and keep the new host service and
controller running while active work finishes and native sandboxes are explicitly
deleted. Verify no native journals, processes or execution Pods remain before
rolling back the kubelet or disabling the chart's host-service Pods. Never remove
execution finalizers to manufacture free capacity. Keep the additive database
columns when rolling back application code; dropping them destroys ownership
metadata needed for cleanup.

## Performance and future work

The [research report](../../handbook/handbook/engineering/macos-sandbox-resume.md)
contains the prototype measurements: resident resume through first command had
medians of 449 ms at 8 GiB and 412 ms at 16 GiB; a 30-second retention experiment
had a 526 ms median. These are not measurements of the integrated production path.
Evicted restore medians were 3.812/6.658/8.790 seconds at 8/16/24 GiB. The larger
memory images and Apple's eager restore dominate that path.

The target remains 1–2 seconds for retained environments. Re-measure through the
account API under concurrent CI demand, including p95/p99 and checkpoint contention.
Restoration after eviction still has no demonstrated 1–2 second path. Follow-up
work includes a supported demand-driven restore runtime, Anka evaluation when a
Build license is available, snapshot-size reduction, and safer automatic collection
of unreferenced runtime/template artifacts. Competitor latency claims are not
proof that they use resident pause or that their measurements include guest readiness.
