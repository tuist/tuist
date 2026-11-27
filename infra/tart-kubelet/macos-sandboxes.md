# macOS sandbox operation

macOS sandboxes use the existing account API and Managed Agents session router.
macOS sandboxes share the `sandboxes` account feature flag with Linux sandboxes;
there is no separate macOS flag. Select `platform: "darwin"` (and optionally an
`xcode_version`, see [Xcode templates](#xcode-templates)) when creating a sandbox
or agent environment, or per Managed Agents session with `platform` on Tuist's
agent-sessions API or the `tuist_platform` session metadata key (`macos` or
`darwin`) on any agent environment. Claude Code (desktop, web, CLI) selects
the OS by environment: connect a `claude_code` environment with
`platform: "darwin"` (`infra/claude-code-runners/README.md`). Defaults are template `macos`, 8 vCPU, 8 GiB RAM and a
10 GB workspace. The other native shapes are 8 vCPU with 16 or 24 GiB RAM.
The workspace is `/Users/runner/work`; Linux requests retain their existing defaults.
The image preinstalls the Tuist CLI and carries a generated guide for agents at
`/opt/tuist/agent-guide.md` ("Tuist CLI and the agent guide" in
`infra/runner-image/AGENTS.md`).

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
   uses the configured, versioned Xcode 26.6 runner image by default, and on a
   rack with `rackFleet.runners.stackedImages` the rack hosts boot its stacked
   build, as their CI pools do. Releases carry an unchanged standalone build
   forward, so it can predate the guard; the stacked build is rebuilt every
   release. Each fleet gets its own control DaemonSet because the image comes
   from the control Pod's config annotation. `sandboxes.macos.image` pins one
   explicit compatible digest for every fleet.
4. Wait for each host to appear in sandbox node presence with the `macos`
   template and a fresh `tuist.dev/macos-sandbox-grant` Node annotation. The
   control Pod turns Ready as soon as tart-kubelet accepts its configuration,
   before preparation, so a chart rollout that waits on the DaemonSet never
   waits on an image pull or for disk room; readiness does not mean the host
   can place sandboxes. Only a host that has prepared its template connects to
   the server, so placement never reaches an unprepared host. When a release
   moves the default to an image the host cannot prepare yet (not in its CI
   store and no room above the cold-pull disk floor, or a failed pull), the
   host connects serving the previous default it still holds
   (`<root>/default-image`), reported as that template's tag, and moves to the
   new image once background preparation has it. On 2026-11-27 16 of 23 rack
   hosts left placement because a deploy moved the default to an image they
   had not staged. Preparation compiles the
   isolated runtime once and downloads the base image at background priority.
   Cold template preparation has a one-hour deadline: staging's first Xcode
   image pull exceeded the normal twenty-minute CI deadline. Removal or
   replacement of the control Pod cancels preparation within one polling
   interval plus the bounded API probe. Transient API failures are retried
   without discarding a healthy download; a fresh control identity check is
   required after the pull before the host connects. Ownership recovery and eviction keep
   running independently. Prewarm the image before enabling an account;
   this one-time transfer is not part of resident resume latency.
5. Run the acceptance checks below on staging, then enable `sandboxes`
   for the intended account through the existing feature-flag administration.
   Create with `{"platform":"darwin"}`, execute a command, pause, resume and delete.

Enabling the feature flag does not provision new hardware. No available grant
means no placement. Disabling it stops new native creation, resumes, commands and
Managed Agents admission. Pause, stop-worker and delete remain available.

## Xcode templates

Each Xcode a macOS sandbox can boot is a template of its own,
`macos-xcode-<xcode-dashes>`, whose image is that Xcode's CI runner image (the
stacked build on a stacked rack). `macos` boots the default Xcode
(`sandboxes.macos.xcodeVersion`), which is also served as its
`macos-xcode-<version>` name, so a sandbox that pins the default keeps it when
the default moves. Callers pick one with an exact `xcode_version`
(`Tuist.Sandboxes.Xcode` in the server); nothing reads a repository's
`.xcode-version`.

- **Which Xcodes.** `sandboxes.macos.xcodeVersions` lists the Xcodes beyond the
  default, each from `runnersFleet.xcodeVersions`. Only the rack serves them; the
  hosts staging and canary borrow serve the default alone.
  The server validates against `TUIST_MACOS_SANDBOX_XCODE_VERSIONS`, which the
  chart renders from the same list.
- **Disk.** Their catalog pools carry `tuist.dev/macos-sandbox-template=true`,
  which ranks their images first in the rack's golden budget
  (`internal/podagent/budget.go`), so every rack host keeps them and each
  template is an APFS clone of the CI golden that costs no disk of its own. The
  chart fails to render when the default plus the list exceeds
  `rackFleet.runners.goldenBudget`. A template whose golden CI does drop keeps
  its blocks (about 73 GB) until it is collected.
- **Preparation.** The host prepares the default image before it connects and
  the rest after it connects, one at a time, retrying every five minutes
  (`prepareTemplates`). Reports list every configured template, `ready` only
  once its image is in the sandbox store, so a missing template never stops the
  host serving the others, and placement skips a host that has not prepared the
  one asked for.
- **Warm VMs.** A warm VM boots the template its Pod's image names. A create
  claims it when the image and shape match, under either name of the default.
  Only the default keeps warm VMs; another Xcode cold-creates.
- **Selection.** The server sends the template's Xcode as the create's
  `xcode_version` (`Tuist.Sandboxes.Xcode.version/1`, the default's for
  `macos`), and the claim runs `/opt/tuist/select-xcode.sh select` in the guest
  (`TartRuntime.selectXcode`), as a CI runner does at its claim
  (`infra/runner-image/AGENTS.md`). The selection lives on the VM's disk. An
  image without the script or the Xcode keeps its own, logged, not failed.
- **Lifetime.** A sandbox keeps its template, and a resume reads only the VM's
  own disks. Dropping an Xcode from the list stops new creates on it; its
  sandboxes keep running and resuming. Templates no longer configured are not
  collected yet: reclaim them only after no journal or checkpoint references
  them.

## Capacity and CI sharing

macOS follows the Linux policy in
[`fleet-sharing.md`](../sandboxd/fleet-sharing.md): queued CI jobs and sandbox
work have equal priority for uncommitted host capacity, and each account's
sandbox vCPU, memory and disk limits bound how much of it that account can take.

The server reserves native CPU, RAM and one VM slot in a PostgreSQL transaction
under a per-node advisory lock. It binds ownership to the Kubernetes Node UID;
reusing a node name cannot move a checkpoint to a replacement machine.
The host's execution reservation Pod is named after the sandbox
(`macos-sbx-<id>`), so a restore the server passes from one refusing Mac to the
next can find it held by another Mac. Releasing it is then a no-op on this Mac;
refusing would strand the record, whose every `Hold` fails the CI launch guard.
A retried restore matches its journal by the archive's checksum and size, not
its presigned URL, which the server signs anew for every attempt.
Account sandbox concurrency quotas also apply to native creation and resume,
including resident resume. Pausing releases the account's active concurrency
quota; a retained VM still holds its full host reservation against CI capacity.

The CI allocator publishes grants for every healthy, unreserved host while fleet
demand is known. CI queued elsewhere in the fleet does not revoke a grant; a
host reservation for a waiting CI shape does. Grants expire after 15 seconds and
are also bound to the current control Pod UID. Unknown or stale demand denies
new native work.
Each grant specifies CPU, RAM and VM slots remaining after non-reclaimable CI
reservations. Placement subtracts existing native reservations from that allowance,
so a host occupied by CI is not selected just because its queue is empty.
CI can revoke admission between server placement and the host's final check.
Work on a running VM (a command, a worker start, a hold, the server's lease)
needs no grant, since the VM already holds its charge; work that has to resume
a paused VM does. CI and sandboxes are served first come, first served: a grant
gates only new capacity, and CI demand arriving later never takes a running
VM's place.
An explicit host capacity refusal returns HTTP 503 and leaves a saved environment
paused for retry; its server charge stays conservative until the next host report.
A paused VM resumes only on its own host, so the refusal (`{:host_busy, why}`)
says why that host can't take it: CI holds its grant, it has no slot left, its
grant is stale, or it is disconnected or replaced.
A create the host refuses for capacity moves on to the next host.
Uncertain cleanup or fencing errors remain failures, not capacity retries.
The kubelet refreshes host memory and process pressure on each heartbeat. macOS
memory warning/critical levels and a process table at least 90% full report
pressure; failed probes report `Unknown` and deny native admission. This also
recovers conditions left `Unknown` by Kubernetes after a kubelet heartbeat gap.
Pressure probes run before the Node metadata/status writes, and status conflicts
are retried. This lets kubelet restart while the controller refreshes capacity
grants without a concurrent grant update terminating the host service.
Idle warm CI runners can yield to a pending sandbox reservation; active CI jobs
are never selected for this preemption.

A session's saved state is encrypted for the Mac that wrote it, so it resumes
only there. The kubelet labels its Node `tuist.dev/macos-sandbox-sessions=true`
while it holds a running or paused session, and CI keeps off those hosts while
others are free: runner Pods prefer Nodes without the label (weight 50, between
the golden image's 100 and a cache volume's 20), and a host reservation picks a
host without it among hosts that converge equally soon and hold the image. Warm
sandbox Pods do not carry the preference.

An evicted session can still move as its disk alone (`internal/macosandbox/archive.go`).
A clone of a stacked image reads the image's disk from Tart's content store and
writes to its own `overlay.asif`, so that file holds every write of the session,
its workspace volume included. `OpArchive` uploads it with the VM's `config.json`
and `nvram.bin` in sandboxd's archive format (`infra/sandboxd/pkg/archive`, holes
left out) through the server's presigned part URLs, and changes nothing on the
host; the server deletes the sandbox once the upload completes, and a resume or
delete meanwhile interrupts it. A create with `from_archive` clones the same
image on another host (the create's `template_tag`; when the template has moved
to a newer release, the host seeds or pulls that earlier digest of the same
repository, usually only its runner layer since releases share the base chunks,
and keeps it for later restores), puts the archived files in place (the archived config
keeps the guest install's machine identity), cold boots and remounts the
workspace volume at `/Users/runner/work`. Processes, simulators and memory are
lost. Only a sandbox whose guest flushed its disks (`/bin/sync` through
`tart exec`) right before it last stopped running is archived, since unflushed
writes live only in the checkpoint; standalone images are refused. Hosts
advertise this with `archives` in their hello. After each eviction save the host
logs `macOS sandbox saved disk usage` with the allocated bytes of `overlay.asif`
and of the checkpoint, the size an archive starts from.

Every native VM also owns a resource-requesting execution Pod. The host serializes
final native and CI launches under one gate and rereads bound Pending, Running
and Terminating Pods, enforcing CPU, RAM and Apple's two-VM limit. A resident
pause retains the full Pod charge. The host repairs missing reservation Pods
from its journals before CI launches; uncertain ownership fails closed.

The background controller checkpoints idle residents after the bounded
30-second idle grace; a revoked grant does not shorten it. Ownership reconciliation and eviction
run independently of image downloads and control connection preparation, so a
failed or slow image update cannot delay returning idle capacity to CI.
It does not interrupt an active managed
worker or exec command, nor a hold (`hold_residency`): an Amp Orb's turn, or
the server's `commands` residency, which on macOS outlives the last command as
a ten-minute session lease so an agent thinking between commands keeps its VM
(`server/lib/tuist/sandboxes/commands.ex`). A hold with `hold_ms` ends that long after
it was last renewed even if the server never releases it; the server sets it
two minutes past the lease, so this only backstops a lost release. CI may therefore wait for active native work to finish
and for the checkpoint to complete. A failed checkpoint or process fence retains
its reservation. No capacity is released merely because a save was requested.
A VM the runtime proves lost (its process gone with no checkpoint, or its VM
missing) holds no CPU or memory and never cold-boots, so it releases its
reservation once and stays in `error`, with its disk, until the server deletes it.
A create that failed never ran, so the server deletes it from the host as soon
as the create fails, or when the host next reports it in `error`, and keeps its
row in `error` without a node. The host also deletes a create or claim still
journaled as failed by itself; a report that no longer lists an errored VM
clears the row's `resident`, so it stops holding CPU, memory and a slot
(`server/lib/tuist/sandboxes/AGENTS.md`, Invariants).
Node hello/report frames always include the resident boolean, including false
after eviction, so the server releases its reservation after the host's fence.

The isolated disk budget counts complete writable root disks and two memory
images per environment, including evicted environments, against half the host
filesystem. Save/restore admission also leaves 20 GiB free beyond two memory
images. The host reports half its filesystem as `disk.budget_bytes`, its free
space, and the template's root disk as `rootfs_bytes`, and server placement
applies the same rule to the environments recorded on the host, so it skips a
host whose disk is full instead of sending it a create to refuse. When the
kubelet's CI store has already pulled the template image, as a CI pool on the
same image does, preparation clones its cached record and the
disk files it names into the isolated store (`seed.go`). The APFS clones share
the CI copy's blocks, so the template costs no disk while CI holds the image,
and they keep those blocks after CI collects its copy. Only otherwise does
preparation pull, and a cold template pull requires 100 GiB beyond the CI
preparation floor of 30% free disk, which a rack host filled to its planned
cache and golden budgets never has. These are conservative admission checks on a shared filesystem,
not a dedicated host filesystem quota. Guest workspaces have an APFS quota;
root disks retain the image's fixed logical ceiling. Automatic Tart pruning is
turned off in the isolated store so it cannot decide environment retention.

### Warm sandbox VMs

`sandboxes.macos.warm.enabled` renders a darwin RunnerPool labelled
`tuist.dev/macos-sandbox-warm=true` for each size in
`sandboxes.macos.warm.memoryMB` (8192, 16384 or 24576; 8 vCPU each). Their Pods
are pre-booted sandbox VMs. The pools share the CI warm-pool budget: the
runners-controller preempts them and rolls their image like a CI pool's, and
their idle Pods give up their slot to CI and to sandbox growth. Unlike an idle
CI runner, a warm VM counts as reclaimable room in sandbox grants immediately,
without the CI preemption grace. The server never routes a job to the pools, so
each keeps only `sandboxes.macos.warm.minWarmPoolFloor` VMs (rendered
explicitly, default 0, since the CRD defaults an absent floor to 1). For that
floor's place on a full rack, the server reports a pool's use from the macOS
sandbox creates of its shape (`Tuist.Runners.MacosSandboxWarmPools`, which
parses the pool name): `hours_with_jobs` ranks it against idle CI pools by the
hours of the last 14 days with a create, and a create in the last hour marks it
in use, so its floor is funded with those of the CI pools running jobs. Queued
CI jobs still take its slot. Production
keeps one 8 GiB VM on the alder rack: a cold create there took 17 to 19 s on a
host with room, and a claim skips its clone and boot, leaving the workspace
volume (`macOS sandbox boot phases` and `claim phases` in the kubelet log time
each step). 8 GiB is the default of Claude Code, Amp Orbs and the tuist-mac
plugin; larger shapes are explicit requests and cold-boot. On a 16 vCPU /
48 GiB rack host every warm VM takes one of the host's two 8 vCPU slots
whatever its memory, so a larger warm size would cost CI no more, only disk.

tart-kubelet's sandbox service, not the CI launch path, boots a warm Pod, and
only on hosts advertising its size's label: `tuist.dev/macos-sandbox-warm-host=v1`
for 8 GiB, `tuist.dev/macos-sandbox-warm-host-<MB>=v1` for the others. A host
advertises a size only while its sandbox service is ready and its disk has room
for one more VM of that size (checked every node heartbeat; a VM reserves its
root disk and two memory images), so warm Pods are not scheduled onto a host
that would refuse each one, and a warm boot checks the room before it clones.
The VM is named `sbw-<pod UID>`, holds no credential and is not journalled; it
fails instead of waiting when the host lacks room, the template or disk. A
create of the same template, image and shape claims a ready VM under the same
grant as a cold create: the host creates the execution Pod, deletes the warm
Pod, and the VM keeps its name for life. A warm VM already has a 10 GB
workspace volume, the size Amp Orbs and agent environments request, so their
claim runs no guest command. APFS cannot change a volume's quota, so a claim
for another size replaces the volume. Other shapes and hosts without a
ready VM cold-boot. Hosts report the shapes of ready VMs, placement tries those
hosts first, and claimed creates record the `warm` boot source. A kubelet
restart deletes unclaimed warm VMs and fails their Pods; the pools refill them.
When the runners-controller retires an idle warm Pod for CI, the host deletes
its VM and completes the Pod's deletion with a zero grace period, as it does
for CI Pods; otherwise the Pod stayed Terminating and held the host for about
six minutes until the controller force-reaped it.

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
Creation and evicted restore wait for a successful ping through the guest bridge,
including its shared executable. A built-in command can succeed before this
bridge is executable after restoration. Readiness retries remain bounded by the
lifecycle context and process lifetime; failure keeps capacity charged.

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

## Disk snapshots

Amp Orb project snapshots (`ORB_SNAPSHOT_ID`) are saved and booted on the host
(`internal/macosandbox/snapshot.go`). A snapshot is a stopped Tart VM named
`sbs-<snapshot id>` in the sandbox store, so a create clones it like the template.

- Every pause runs `/bin/sync` in the guest first and journals `disks_synced`
  (see archives); a resume clears it. A failed sync still pauses.
- `save_disks {sandbox_id, snapshot_id}` needs a paused sandbox with synced
  disks. It evicts a resident VM first (the checkpoint and fence free its slot),
  then APFS-clones `config.json`, `nvram.bin` and the stacked VM's
  `manifest.json` and private `overlay.asif` (base layers stay shared in the
  content store) into `snapshots.tmp/<id>`, writes `disk-snapshot.json` and
  renames it to `vms/sbs-<id>`. A VM with a standalone `disk.img` is refused:
  that disk is the whole image, which could never be archived or copied, so
  only its host could boot from it. `state.vzvmsave` and
  the runtime's control files stay behind, so a clone cold boots. The workspace
  is an APFS volume inside the root disk, so it comes along with its quota.
  It answers `bytes`, the overlay's allocated size. Saving an existing ID
  answers it unchanged. Startup empties `snapshots.tmp`.
- `save_disks {..., shutdown: true}` stops a resident VM with a clean guest
  shutdown instead of the eviction: it resumes it, runs `sudo -n
  /sbin/shutdown -h now` in the guest and waits up to 75 s for the VM process
  to exit, never forcing it off, so the saved disks hold unmounted file
  systems rather than a running guest's synced ones. The record keeps no
  checkpoint (`shut_down`), so a resume fails and a host restart finds the VM
  lost. Only repository snapshot builders, which are deleted next, ask for it.
- `delete_disks {snapshot_id}` removes it; an absent one succeeds.
- `create {from_disk_snapshot}` clones `sbs-<id>`, runs the snapshot's image tag,
  sets shape and identity, boots, then mounts the existing `TuistSandboxWorkspace`
  volume at `/Users/runner/work` instead of adding one. A host without the
  snapshot answers `disk snapshot not found` before reserving anything. Warm VMs
  are never used for these creates.
- `hello` and `report` list `disk_snapshots` with their `bytes`, and
  `disk.snapshots_bytes` sums them. `diskRoom` and the server's
  `MacosCapacity.disk_room?` count them against half the filesystem; the server
  does not reserve the Linux ceiling for them, because only the host can measure
  what an overlay holds.

Placement (`Sandboxes.place_and_create/4`, darwin clause): a create from a
snapshot goes through `MacosCapacity.place/2` restricted to the hosts holding it.
When none can take it or the clone fails, an archived snapshot is restored on
another host like an archived session (`create {from_archive, template_tag}`,
placed by `place_macos_restore/3`); without an archive, or when no host can restore
it, the template boots on any host at once, since waiting for the snapshot's
host could take as long as a CI job.

Claude Code repository snapshots (`Tuist.Sandboxes.ClaudeCodeSnapshots`) are
built as on Linux: a builder VM with the build's id clones the repository and
runs the environment's setup script as `runner` for up to an hour, then pauses
with synced disks and is saved like an Orb, except that the save shuts its
guest down cleanly (`shutdown`) instead of checkpointing it. A builder serves no session, so
`MacosCapacity` places it only where it leaves a granted slot free: no other VM
on the host and a grant of two slots. While CI or sessions hold a slot it waits
and retries every minute, and once it runs, CI waits for it like any VM.

Replication follows Linux snapshot copies and reuses the session archive above.
While the archive tier is on, a ready snapshot is uploaded (`archive_disks`) as
an evicted session is (`uploadDisk`): `config.json`, `nvram.bin` and
`overlay.asif`, sized by the snapshot's measured `disk_bytes`. A popular
snapshot (`DiskSnapshots.copy/1`) is then copied
(`copy_disks {..., template_tag, bytes}`) onto hosts picked by rendezvous
hashing of its lineage among those serving its template and restoring archives
(`MacosCapacity.snapshot_hosts/1`). A copy is a restore that stays stopped
(`cloneArchived`): the host clones the image the snapshot was saved from into
`vms/sbs-<id>`, pulling that digest first when its template moved on, puts the
archived files over the clone's and writes `disk-snapshot.json` last, so a
partial copy is never reported or cloned; a failed one is removed, and startup
removes `sbs-*` VMs without metadata. The server admits a copy against the
host's budget with the measured bytes and the copies still downloading there
(`MacosCapacity.reserve_snapshot_copy/3`); the host checks again first.
Qualification on a rack host (`TestAppleRuntimeAcceptance`) is still owed:
clone of a saved or copied snapshot, cold boot and the workspace remount have
only been exercised with fakes and, for the remount commands, in a guest.

## Cached checkouts

With the runner cache enabled (`--custom-cache-url`), every sandbox VM, warm
ones included, boots with a `sandbox-checkout` share at
`<runner-cache-root>/custom/sandbox-checkouts/<VM>/`, recorded in the sandbox's
journal and kept for the VM's life, since a restore needs the shares it was
saved with. VMs booted before this keep booting without one and their sessions
clone. A `start_worker` carrying the server's checkout grant
(`protocol.CheckoutGrant`) puts a CoW clone of the CI checkout master in the
share (`podagent.CustomVolumes.SeedSandbox`), or queues a restore of the
volume's HEAD on a cold host, and ends the use; `sbx-worker` copies the tree to
the runner's clone. The guest leaves its export in the share, and the host takes
it only after an eviction's save or a delete has fenced the VM
(`CollectSandbox`), then builds from it like a default-branch CI job's export.
Not yet qualified on a host: attaching the clone from the share in a VM
claimed from the warm pool.

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

Staging recorded real API acceptance at 8/16/24 GiB: five resident cycles per shape
had medians of 534/788/520 ms through the first command. Heap preservation passed
after eviction, kubelet restart and CI-priority eviction, followed by cleanup.
One evicted restore per shape took 12.270/6.907/10.400 seconds, separately from
HTTP admission retries. These small samples do not establish tail latency or
performance under an Xcode/simulator workload.

Earlier prototype measurements of resident resume through first command had
medians of 449 ms at 8 GiB and 412 ms at 16 GiB; a 30-second retention experiment
had a 526 ms median. These are not measurements of the integrated production path.
Evicted restore medians were 3.812/6.658/8.790 seconds at 8/16/24 GiB. The larger
memory images and Apple's eager restore dominate that path.

The target remains 1–2 seconds for retained environments. Extend the account API
measurements to sustained CI demand, p95/p99, longer idle periods and checkpoint contention.
Restoration after eviction still has no demonstrated 1–2 second path. In
production on 2026-11-12, resumes after an eviction (30 s idle, or sooner when
CI revoked the grant) restored a checkpoint in 4–8 s at 8 GiB and 10–16 s at 24 GiB. A create or
restore on a host whose freed slot CI had refilled also waited 5–12 s for the
runners-controller to retire that idle runner, which made 22–26 s resumes; the
reservation now reconciles only the pools with runners on its host. Follow-up
work includes a supported demand-driven restore runtime, Anka evaluation when a
Build license is available, snapshot-size reduction, and safer automatic collection
of unreferenced runtime/template artifacts. Competitor latency claims are not
proof that they use resident pause or that their measurements include guest readiness.
