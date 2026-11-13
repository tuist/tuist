| `BLOB_CACHE_GIB` | `0` | Node cache of remote-execution input blobs under `DATA_DIR/blobs`, emptied at startup; see "Guest to host: blob cache". It comes out of `DISK_BUDGET_GIB`: the daemon reports the budget less the cache, so placement never counts on the cache's bytes, and refuses to start unless the cache is smaller. Its usage is reported in `disk.templates_bytes`. `0` disables it. || `BLOB_CACHE_GIB` | `0` | Node cache of remote-execution input blobs under `DATA_DIR/blobs`, emptied at startup and counted in `disk.templates_bytes`; see "Guest to host: blob cache". `0` disables it. |
# sandboxd

Per-node daemon that runs Firecracker microVM sandboxes for coding-agent
sessions on the Linux bare-metal fleet. One sandbox is one persistent VM per
agent session: created from a golden template snapshot, paused to local NVMe
when the session goes idle, resumed when the next turn arrives. The first
consumer is Claude Managed Agents `self_hosted` environments: Anthropic runs
the agent loop, the Tuist server claims work items from the environment's
queue and routes each session to its sandbox, and a worker inside the VM
executes the bash and file tools.

GitHub Actions runners stay on Kata (`infra/runners-controller`); sandboxd is
a separate substrate on the same nodes. The DaemonSet Pod starts at
`sandboxes.memoryGiB` (request equals limit) under a PriorityClass
with `preemptionPolicy: Never`: runner Pods carry no priority and become
job-owning in place, so the daemon must never evict one. On a full node it
waits, first in the scheduling queue, for a job to finish. `memoryGiB` defaults
to 1 GiB, which holds the daemon and a template build but no sandbox, so a node
gives sandboxes nothing until one needs memory; the server then grows the Pod in
place up to `sandboxes.maxMemoryGiB` (see "Server side").

## Pieces

| Piece | Where | Runs as |
|---|---|---|
| `sandboxd` | `infra/sandboxd` (Go) | privileged DaemonSet Pod in `tuist-sandboxes` on nodes selected by `sandboxes.nodePools` |
| template image | `infra/sandbox-image` (Dockerfile) | init container of the DaemonSet Pod; copies `vmlinux` + `rootfs.ext4` onto the node |
| `sbx-init` | `infra/sandbox-image/cmd/sbx-init` (Go) | PID 1 inside the guest |
| `sbx-agent` | `infra/sandbox-image/cmd/sbx-agent` (Go) | vsock server inside the guest; exec, files, time |
| `sbx-worker` | `infra/sandbox-image/cmd/sbx-worker` (Go) | Anthropic SDK `EnvironmentWorker.HandleItem` inside the guest, one process per residency |
| control plane | `server/lib/tuist/sandboxes` (Elixir) | `Tuist.Sandboxes` context, node connections, Anthropic work-queue poller, pause scheduling, account API |

## Node layout

Everything lives under `/data/sandboxes` on the node (`/data` is XFS with
reflink, so rootfs clones are instant copy-on-write):

```
/data/sandboxes/templates/<name>/<tag>/
  vmlinux             kernel from the template image
  rootfs.ext4         pristine rootfs from the template image
  metadata.json       {name, tag, kernel, built_at}
  shapes/<vcpus>x<memory_mb>/
    rootfs.boot.ext4  rootfs as it was when this shape's snapshot was taken
    memfile           guest memory at the snapshot
    snapshot          Firecracker vmstate at the snapshot
    metadata.json     {name, tag, vcpus, memory_mb, kernel, firecracker_version, built_at}
    ready             present once the snapshot is complete
/data/sandboxes/jail/firecracker/<sandbox_id>/root/
  vmlinux             hard link to the template kernel
  rootfs.ext4         reflink clone of rootfs.boot.ext4
  workspace.ext4      sparse raw ext4 mounted at /workspace in the guest
  mem                 hard link to the template memfile, replaced by the sandbox's own memory file on the first pause
  snapshot            template vmstate, replaced on the first pause
  run/firecracker.socket, v.sock
  firecracker.log     Firecracker and guest console output, drained through a pipe and started over past 8 MiB
  metadata.json       {id, template, tag, vcpus, memory_mb, state, generation, firecracker_version, disks_synced}
/data/sandboxes/snapshots/<snapshot_id>/
  vmlinux             hard link to the kernel the source sandbox booted
  rootfs.ext4         reflink clone of the source sandbox's rootfs
  workspace.ext4      reflink clone of the source sandbox's workspace
  disk-snapshot.json  {id, template, tag, workspace_gb, source_sandbox, created_at}
/data/sandboxes/blobs/<scope>/<sha256>-<size>
                      remote-execution input blobs (BLOB_CACHE_GIB), emptied at startup
/data/sandboxes/checkouts/<key digest>.ext4, <key digest>.json
                      prepared checkout workspaces (CHECKOUT_WORKSPACES_GIB); unfinished
                      .build-* directories are removed at startup
```

The jail directory is the jailer's chroot, so every sandbox sees the same
paths (`/vmlinux`, `/rootfs.ext4`, `/workspace.ext4`, `/mem`, `/snapshot`) and
one template snapshot restores into any sandbox directory. Snapshots record
absolute drive paths and a drive cannot be swapped between load and resume;
identical in-jail paths are what make the template shareable.

## Template snapshot

The template image ships a kernel and a pristine rootfs. The daemon builds
snapshots on the node it runs on, because Firecracker snapshots are tied to
the CPU model and Firecracker version, and one snapshot per shape, because a
snapshot fixes the vCPU count and memory size. A shape's snapshot is built
lazily by the first `create` that needs it (and eagerly at startup for the
shapes in `PREBUILD_SHAPES`): reflink `rootfs.ext4` to `rootfs.boot.ext4`,
attach an empty sparse workspace disk, boot with the shape, wait for
`sbx-agent` to answer `ping` over vsock, pause, take a full snapshot into
`memfile` + `snapshot`, kill the VM and write `ready`. The booted rootfs is
kept as the clone source because the guest's page cache in `memfile` matches
that disk, not the pristine one. The template VM is never resumed. The guest
does not mount the workspace disk at template time; `create` formats and
mounts the sandbox's own disk after the restore (see `configure`).

Boot args: `console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw
rootfstype=ext4 init=/sbin/sbx-init sbx.dns=<ip,ip> sbx.hostname=sandbox`.
The DNS list is the daemon Pod's own resolvers (cluster DNS), so guests
resolve both cluster Services and public names through the pod's NAT.

A shape snapshot records the Firecracker version that took it, and startup
removes shapes another version took, since that version cannot load them; the
next create rebuilds them. Restored guests keep the boot args baked into their
memory image until they cold boot.

## Sandbox lifecycle on the node

- `create {sandbox_id, template, vcpus, memory_mb, workspace_gb, hostname}`:
  make the jail dir, hard link `vmlinux` and `mem`, reflink `rootfs.ext4`,
  create a sparse unformatted `workspace.ext4`, set up the network namespace,
  spawn the jailer + Firecracker, `PUT /snapshot/load` with the shape's
  vmstate and the `File` memory backend (`resume_vm: true`), then over vsock
  `set_time`, `configure {hostname, dns, format_workspace: true}` (the guest
  flushes the block device's cached sectors, formats `/dev/vdb` and mounts it
  at `/workspace`) and `ping`. Reports `boot_ms`.
- `pause {sandbox_id}`: refuse if a worker or exec is still running, and
  from then on refuse new execs and workers until the pause ends. `PATCH
  /vm Paused`, `PUT /snapshot/create` (Full) into `mem.new` + `snapshot.new`,
  kill Firecracker, tear down the netns, rename over `mem` and `snapshot`.
  Reports `snapshot_ms` and `mem_bytes`. If Firecracker does not die the
  sandbox moves to `error` (`sandbox_died`); if the renames fail it becomes
  `paused` with `cold_boot` set.
- `resume {sandbox_id}`: recreate the netns with the same tap name and
  addresses, spawn jailer + Firecracker, `PUT /snapshot/load` with the
  sandbox's own `mem` (`File` backend, `resume_vm: true`), then `set_time`,
  `configure` (flushes ARP) and `ping`. Reports `restore_ms`. Resuming a
  sandbox that is already running succeeds without doing anything, so a
  retried resume whose first answer was lost is harmless.
- `pause {sandbox_id, sync_disks: true}` first runs `/bin/sync` in the
  guest and records `disks_synced` in the metadata (cleared by the next
  resume), so the disks alone hold everything written. A failed sync still
  pauses and leaves the flag unset.
- `save_disks {sandbox_id, snapshot_id}`: refuse unless the sandbox is
  paused with `disks_synced`; hard link its kernel and reflink its rootfs
  and workspace into `snapshots/.tmp-<id>`, write `disk-snapshot.json`,
  fsync, and rename over `snapshots/<id>`. No memory is kept. Startup
  removes `.tmp-*` leftovers. `delete_disks {snapshot_id}` removes the
  directory and succeeds when it is absent. `hello` and `report` list the
  snapshots under `disk_snapshots`; the disk report counts their exclusive
  bytes as `snapshots_bytes`.
- `create {..., from_disk_snapshot}`: link the snapshot's kernel and
  reflink its disks into the jail instead of the template's (the template
  name and workspace size must match the snapshot), then cold boot like a
  `cold_boot` resume. No template shape snapshot is needed, and the guest
  keeps its workspace. The first pause writes the sandbox's own memory
  image.
- `archive {sandbox_id, part_size, part_urls}`: refuse unless the sandbox is
  paused with `disks_synced`, since only the disks are archived; stream
  `vmlinux`, `rootfs.ext4` and `workspace.ext4` (no memory image) as one
  zstd object (`internal/archive`: magic `SBXARC1`, a JSON
  header, file records with data blocks at their offsets, holes and zero
  blocks left out) cut into `part_size` parts, each PUT to the next
  presigned UploadPart URL (two parts in memory at most, three attempts per
  part). Answers the parts' ETags, the object's `bytes` and `sha256`,
  `stored_bytes` and `disks_synced`. The sandbox stays paused on the node;
  the server deletes it once the upload is complete. A `resume` or `delete`
  cancels an archive in flight instead of waiting for it. Transport errors
  never carry the signed URL.
- `archive_disks {snapshot_id, part_size, part_urls}`: upload a disk
  snapshot's kernel, rootfs and workspace in the same archive format and
  answer the same fields as `archive`. The files are opened under the
  snapshot lock and streamed after it is released, so a delete or a newer
  save meanwhile only unlinks them; the server discards an upload whose
  snapshot changed. The snapshot stays on the node. Any node can then
  `create` from the object with `from_archive`, which is how a project
  snapshot reaches a node other than the one that saved it.
- `create {..., from_archive: {url, bytes, sha256}}`: download the archive
  (three attempts), check its size and SHA-256, extract it into a fresh
  jail (the template name and workspace size must match), then cold boot
  like a disk-snapshot clone. A failure discards the jail; the archive is
  never touched.
- `delete {sandbox_id}`: kill the VM if running, tear down the netns, remove
  the jail dir. Deleting an id the node does not hold succeeds and removes
  whatever is left on disk under it.
- `exec` streams a command's output back to the server; `start_worker` runs
  `/usr/local/bin/sbx-worker` with the Anthropic environment variables and
  emits `worker_exited` when it ends; `stop_worker` sends SIGTERM and waits.

Firecracker loads a snapshot only into a fresh process, so every resume spawns
a new jailer. `track_dirty_pages` is off (full snapshots). The memory file the
VM is mapped from must not change while it runs, which is why a pause writes
`mem.new` and renames after the process is dead.

## Network

Firecracker runs inside the DaemonSet Pod's network namespace, so the Pod's
Cilium endpoint and NetworkPolicy govern every sandbox's traffic. Inside the
Pod, each sandbox gets its own netns `sbx-<id12>`:

- `tap0` in the netns at `10.0.0.1/30`; the guest is always `10.0.0.2` with
  MAC `06:00:AC:10:00:02`. Fixed guest addressing is what lets one snapshot
  restore anywhere.
- a veth pair `vh<n>` (pod side) / `veth0` (netns side) on a /30 carved from
  `172.31.0.0/16` by the sandbox's slot index `n`: pod side `172.31.x.y+1`,
  netns side `172.31.x.y+2`.
- in the netns: `ip_forward=1`, default route via the pod side, `MASQUERADE`
  out of `veth0`.
- in the Pod netns: `ip_forward=1`, `MASQUERADE` for `172.31.0.0/16` out of
  `eth0` (installed once at startup).

A resume recreates exactly the same names and addresses; the guest flushes
its ARP cache on `configure`.

The daemon's own listeners (metrics, admin API) bind to the pod IP, and the
pod namespace drops everything the slot network sends to local processes
(`INPUT -s 172.31.0.0/16 -j DROP`) and between sandboxes (`FORWARD -s
172.31.0.0/16 -d 172.31.0.0/16 -j DROP`), both inserted ahead of the
forwarding accepts. A guest can only reach what lies beyond the pod, under
the pod's NetworkPolicy; its control channel is vsock, never the network.

Every guest shares the daemon Pod's Cilium identity, so the NetworkPolicy
cannot tell the daemon's traffic from a guest's. What only the daemon needs
is fenced in the pod namespace instead, again ahead of the forwarding
accepts: guest traffic to `DAEMON_ONLY_TCP_PORTS` on any address, and to
each address `SERVER_URL` resolves to (its Service IP and port), is
dropped. The pod namespace sees guest packets before Cilium translates a
Service address, so the chart lists both the server Pods' target port and
the archive store's port, and the daemon resolves `SERVER_URL` at startup.
Guests reach the Tuist API through its public URL like any client
(`TUIST_URL` is the app URL); `GUESTS_REACH_SERVER=true`
(`sandboxes.networkPolicy.guestServerAccess`) lifts the server fence for a
deployment whose public URL is the in-cluster Service.

## Host to guest: vsock

`sbx-agent` listens on vsock port 5000 (guest CID 3). The host connects
through Firecracker's UDS (`v.sock`) with the `CONNECT 5000` handshake. One
connection per request. Newline-delimited JSON, base64 for bytes.

Requests:

```
{"id":"r1","op":"ping"}
{"id":"r1","op":"set_time","unix_nanos":1757000000000000000}
{"id":"r1","op":"configure","hostname":"sbx-abc","dns":["10.128.0.10"],"format_workspace":true}
{"id":"r1","op":"write_file","path":"/workspace/x","mode":420,"data_b64":"..."}
{"id":"r1","op":"exec","cmd":["/bin/bash","-lc","ls"],"env":{"K":"V"},"cwd":"/workspace","timeout_ms":0}
{"id":"r1","op":"kill","target":"<exec id>","signal":15}
```

Responses (streamed for `exec`):

```
{"id":"r1","type":"pong","uptime_s":12.3,"agent_version":"..."}
{"id":"r1","type":"ok"}
{"id":"r1","type":"started","exec_id":"e1"}
{"id":"r1","type":"stdout","data_b64":"..."}
{"id":"r1","type":"stderr","data_b64":"..."}
{"id":"r1","type":"exit","code":0}
{"id":"r1","type":"error","message":"..."}
```

`exec` runs as root with `/workspace` as the default cwd. `set_time` steps the
guest wall clock (`clock_settime`); it runs before `ping` on every resume,
because the guest clock is stale by exactly the pause length until then.
`configure` with `format_workspace: true` flushes `/dev/vdb`'s cached sectors
(`BLKFLSBUF`), formats it and mounts it at `/workspace`; without the flag it
mounts the disk only if nothing is mounted there yet. The flush matters
because the template VM saw an empty disk at the same path and the block
layer may have cached its first sectors.

## Guest to host: blob cache

With `BLOB_CACHE_GIB` set, a remote-execution guest reads its large inputs
from the node (`internal/blobcache`), so the CAS sends each blob to a node once
instead of once per action. The guest connects to vsock port 5001 on the host
(CID 2), which Firecracker forwards to `<jail root>/v.sock_5001`. The daemon
listens there only while an action exec runs: `/usr/local/bin/sbx-executor`
with no arguments, `SBX_EXECUTION_TOKEN` and `SBX_EXECUTION_REQUEST` (its
`endpoint`, `account` and `instance`), on a VM of the template tag the daemon
is configured with. The scope comes from that exec, never from the guest.

One request per connection, a JSON line:

```
{"op":"read","hash":"<sha256>","size":N,"offset":O,"length":L}
{"op":"seal"}
```

A read answers `{"ok":true}` and exactly `L` bytes of the blob from `O`, or
`{"error":"..."}`, and the guest then reads that blob from the CAS. A miss
downloads the whole blob with the exec's credential, verifies its digest, and
serves every concurrent request for it from that one download. Blobs are kept
per CAS scope (endpoint, account, instance), so a hit never serves another
project's blob. The least recently used are evicted to stay within the
budget and to leave 20% of the data filesystem free, which the cache shares
with runner cache volumes, containerd and kubelet (kubelet evicts Pods below
15%); when nothing is left to evict, the guest reads that blob from the CAS. `seal` ends serving for the exec; the executor sends it before the
action's command starts, so the build cannot read the project's CAS through
the host.

## Guest to host: checkout

With `CHECKOUT_AGENT_URL` set, a worker whose `start_worker` carries a
`checkout` grant (`protocol.CheckoutGrant`) starts from the node's checkout
master of its repository and exports back to it (`internal/checkout`), under
the rules CI checkouts follow (`infra/runners-controller/cache-volumes.md`,
"Cached checkouts"). The daemon adds `SBX_CHECKOUT_PATH` (the grant's `path`),
`SBX_CHECKOUT_COMMIT` (its `commit`) and `SBX_CHECKOUT_VSOCK=5002` to the
worker env and listens on `<jail root>/v.sock_5002`, where Firecracker
forwards the guest's connections to CID 2 port 5002, for as long as that
worker runs: the worker's exit disarms it before freeing the worker slot, so a
pause or delete never leaves it armed. Without an agent, with an invalid grant
(no `id`, a `path` that is not absolute and clean) or when the listener fails,
the env is unchanged and the guest clones as before; the worker always starts.

One request per connection, a JSON line; at most one seed and one export per
arming, and four connections at a time:

```
{"op":"seed"}
{"op":"export"}   followed by the export's tar stream
```

A seed answers `{"ok":true}` and a tar of the master's repository directory
(paths relative to it, `.git` included; directories, regular files and symlinks
with their permission bits, no owners), then closes; or `{"error":"cold"}` when
the node holds no master, or `{"error":"unavailable"}`. A tree is complete only
when it ends with its end-of-archive blocks: a stream that fails midway, or
reaches 60 GB, is cut before them. An export is the CI format (`head`,
`shallow`, `pack`, `lfs/<oid>`, see `infra/runner-cache/checkout_export.go`).
Firecracker does not pass a guest's write shutdown on to the host socket, so
the daemon reads the export up to its end-of-archive blocks, forwards exactly
those bytes, and answers `{"ok":true}` once the agent queued it or
`{"error":"export refused"}`; an export past 30 GB and 64 MiB fails rather than
being cut. A seed gets 10 minutes and an export 6, the agent's part included.

With `CHECKOUT_WORKSPACES_GIB` set, the daemon also keeps prepared workspaces
(`internal/checkout/workspaces.go`) so a session copies the tree into its guest
only once per node. A seed it relays is recorded to `checkouts/.build-*` and,
once complete, built in the background into an ext4 image of the sandbox's
workspace size, with the tree at the grant's path below `/workspace`, owned by
the template's runner user (`runner_uid`/`runner_gid` in the template's
`metadata.json`; templates without them get no images), and
`protocol.CheckoutPreparedFile` in its `.git` naming the master's commit and LFS
objects. It is formatted on the host with `mkfs.ext4 -d` from the agent's tree,
never from a guest's disk. An image is keyed by the grant's scope and clear
generation, that path, the disk size and the owner, is used for
`CHECKOUT_WORKSPACES_TTL` (6h) after it is built and then removed, so the next
seed rebuilds it from a newer master, and images beyond the budget go oldest
first. When `start_worker` carries a grant whose image is here and the sandbox
was created from the template snapshot and has run nothing yet, the daemon
reflinks the image beside the jail's `workspace.ext4`, has the guest
`umount /workspace`, renames the clone over the disk, `PATCH /drives/workspace`
reopens it, and `configure` (no format) flushes and mounts it. The guest's
worker then finds the repository in place and adopts the marker as its export
state. A guest that cannot unmount keeps its empty workspace and seeds as
before; a failure after the rename puts the empty disk back. The images count
in `disk.templates_bytes` and come out of `DISK_BUDGET_GIB` like the blob
cache.

The daemon reaches the node's runner-cache agent through its Service
(`internalTrafficPolicy: Local`, port 8090) with `POST
/sandbox-checkout/seed` and `POST /sandbox-checkout/export`, each starting
with `{"pod_name": POD_NAME, "grant": ...}`. The agent authorizes the daemon's
Pod by name, node and address. Guests share that address and the Pod's
NetworkPolicy identity, so the chart lists 8090 in `DAEMON_ONLY_TCP_PORTS`:
nothing the guest sends reaches the agent except the export bytes the daemon
relays, which the agent verifies as it does a CI job's.

## Node to server: WebSocket

The daemon dials `GET /api/internal/sandboxes/nodes/connect` on the in-cluster
server Service with `Authorization: Bearer <projected SA token, audience
tuist-sandboxes>` and `X-Tuist-Node-Name`. The server validates the token
with a Kubernetes TokenReview and requires the `tuist-sandboxes` namespace.
Text frames, JSON. The node reconnects with backoff; the server treats a
reconnect as a fresh `hello`.

Node to server:

```
{"type":"hello","node":"...","daemon_version":"...","firecracker_version":"...",
 "capacity":{"memory_bytes":N,"cpus":N},
 "elastic":{"pod_name":"...","memory_floor_bytes":N,"memory_ceiling_bytes":N},
 "disk":{"total_bytes":N,"available_bytes":N,"sandboxes_bytes":N,"templates_bytes":N,"budget_bytes":N},
 "templates":[{"name":"default","tag":"sha-...","ready":true,"rootfs_bytes":N}],
 "sandboxes":[{"id":"...","state":"running","template":"default","template_tag":"...",
               "vcpus":2,"memory_mb":4096,"worker_running":false,"cpu_ms":1234}]}
{"type":"result","id":"c1","ok":true,"data":{...}}
{"type":"result","id":"c1","ok":false,"error":"..."}
{"type":"stream","id":"c1","stream":"stdout","data_b64":"..."}
{"type":"event","event":"worker_exited","sandbox_id":"...","exit_code":0,"duration_ms":1234}
{"type":"event","event":"sandbox_died","sandbox_id":"...","reason":"..."}
{"type":"event","event":"template_ready","name":"default","tag":"..."}
{"type":"report","capacity":{...same shape as hello...},"sandboxes":[...same shape as hello...],"memory":{"used_bytes":N},"disk":{...same shape as hello...}}
```

Server to node:

```
{"type":"command","id":"c1","op":"create","args":{"sandbox_id":"...","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":10,"hostname":"sbx-abc"}}
{"type":"command","id":"c2","op":"resume","args":{"sandbox_id":"..."}}
{"type":"command","id":"c3","op":"pause","args":{"sandbox_id":"..."}}
{"type":"command","id":"c4","op":"delete","args":{"sandbox_id":"..."}}
{"type":"command","id":"c5","op":"exec","args":{"sandbox_id":"...","cmd":["/bin/bash","-lc","ls"],"env":{},"cwd":"/workspace","timeout_ms":60000}}
{"type":"command","id":"c11","op":"exec","args":{"sandbox_id":"...","cmd":["/usr/local/bin/sbx-executor"],"env":{...},"cwd":"/workspace","timeout_ms":780000,"claim":{"nonce_sha256":"<hex>","env":"SBX_EXECUTION_REQUEST","timeout_ms":30000}}}
{"type":"command","id":"c6","op":"start_worker","args":{"sandbox_id":"...","env":{"ANTHROPIC_SESSION_ID":"...","ANTHROPIC_WORK_ID":"...","ANTHROPIC_ENVIRONMENT_ID":"...","ANTHROPIC_ENVIRONMENT_KEY":"...","ANTHROPIC_WORK_SECRET":"...","ANTHROPIC_BASE_URL":"...","SBX_MAX_IDLE":"30s"}}}
{"type":"command","id":"c7","op":"stop_worker","args":{"sandbox_id":"..."}}
{"type":"command","id":"c8","op":"status","args":{"sandbox_id":"..."}}
{"type":"command","id":"c9","op":"reclaim","args":{"target_bytes":N}}
{"type":"command","id":"c10","op":"archive","args":{"sandbox_id":"...","part_size":N,"part_urls":["https://..."]}}
{"type":"command","id":"c12","op":"archive_disks","args":{"snapshot_id":"...","part_size":N,"part_urls":["https://..."]}}
```

A running sandbox's `cpu_ms` is its Firecracker process's user and system
time from `/proc/<pid>/stat` (vCPU threads included), restarting from zero
with each new VM process; the server uses it to pause idle Amp Orbs. Paused
sandboxes, and hosts without `/proc`, omit it.

Every command gets exactly one `result`. `exec` emits `stream` frames before
its result (`data.exit_code`). `start_worker` results as soon as the worker
process is running; `worker_exited` follows as an event. Credentials travel
only in `start_worker` args, are handed to the guest over vsock, and are never
written to the node's disk by the daemon.

An `exec` with a `claim` waits up to `claim.timeout_ms` for a caller to post
`{sandbox_id, nonce, value}` to `POST /v1/claims` on `DIRECT_EXEC_ADDR`
(advertised as `direct_exec_endpoint` in `hello`). The nonce must hash to
`claim.nonce_sha256`; the claim is single-use. The command then runs with
`value` in `claim.env`, its standard output goes only to the caller
(`{exit_code, stdout}`), and the result carries the exit code. Unclaimed, the
result is `{"unclaimed": true}` and nothing ran.

The daemon rereads its cgroup's memory limit every 250 ms and sends a
`report` as soon as it changes, so a resize of its Pod reaches the server's
budget without waiting out the 30 s interval. `reclaim` writes the excess over
`target_bytes` to the cgroup's `memory.reclaim` and answers the limit and
what the cgroup still charges; the server sends it before shrinking the Pod,
because the kubelet will not lower a limit below current usage and paused
guests leave page cache behind.

## Worker inside the guest

`sbx-worker` wraps the Anthropic Go SDK's `EnvironmentWorker.HandleItem`
with `Workdir=/workspace` and `MaxIdle` from `SBX_MAX_IDLE` (default 30s). It
reads `ANTHROPIC_SESSION_ID`, `ANTHROPIC_WORK_ID`, `ANTHROPIC_ENVIRONMENT_ID`,
`ANTHROPIC_ENVIRONMENT_KEY`, `ANTHROPIC_WORK_SECRET` and optionally
`ANTHROPIC_BASE_URL` from its environment, heartbeats the work-item lease,
attaches to the session's event stream, executes tool calls and exits after
`MaxIdle` following an `end_turn` idle. The work item was already claimed and
acknowledged by the server's poller; the worker never polls.

With `SBX_CLAUDE_CODE_WORK_ORDER` set, `sbx-worker` instead runs `claude
self-hosted-runner` for one Claude Code session (capacity 1, Anthropic's git
proxy, release after `SBX_CLAUDE_CODE_RELEASE_IDLE_MIN` idle minutes) under
`<workdir>/claude-code`. The work order reaches the runner only as
`SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET`. On Linux it drops from root to `user`;
a guest without the pinned binary downloads and checksums it first.

## Server side

- A poller process per connected Anthropic environment long-polls the work
  queue, acknowledges session items immediately, force-stops anything that is
  not a session, and hands the item to the router.
- The router finds the sandbox for `data.id` (the session) or creates one from
  the environment's template and shape, resumes it if paused, and sends
  `start_worker`.
- `worker_exited` ends the residency; the sandbox is paused after a grace
  period (default 30s) unless a new residency started meanwhile.
- Placement budgets memory against `capacity.memory_bytes`, the daemon's
  cgroup limit: every creating, resuming or running sandbox is charged its
  guest memory plus 64 MiB, 512 MiB stay reserved for the daemon and the
  VMMs, and a node the sum would overflow is skipped. Idle running sandboxes
  (no residency) are paused, longest idle first, when nothing fits. A node
  without room for another memory image on disk (`disk.available_bytes`,
  plus 1 GiB headroom) is skipped too, as is one whose `disk.budget_bytes`
  cannot take the new sandbox's ceiling on top of the ceilings of every
  sandbox placed there, including errored ones whose jail it still reports. A sandbox's ceiling is its rootfs
  image (`templates[].rootfs_bytes`), its workspace image (`workspace_gb`)
  and its memory image, all fixed-size files it can never write past, so
  the reservation holds however the sandboxes later fill them. The
  poller leaves a work item unacknowledged when its sandbox would not fit
  anywhere, so the queue holds it until a pause frees memory.
- A node whose `hello.elastic` carries a ceiling above its floor has an
  elastic carve-out (`sandboxes.maxMemoryGiB` in the chart). The Pod starts
  at the floor; when nothing fits even after pausing idle sandboxes, the
  server grows the Pod's memory in place through its `resize` subresource,
  in whole GiB up to the ceiling, records the size it asked for in
  `sandbox_nodes`, and places once the daemon reports the new limit. The
  kubelet applies a growth that fits the node at once and defers one that
  does not; the server reads the Pod's resize status, gives a deferred
  growth back and tries the next node, and the last deferral stays asked
  for while the runners controller retires idle warm runners on that
  node, and the scheduler, which counts the requested size, places no runner
  Pod into the room meanwhile. Placements budget against the smaller of the
  reported limit and the size asked for. A minute-by-minute job shrinks a
  carve-out back toward what its running sandboxes hold, never below the
  floor, retaining only an in-flight growth for up to 15 seconds: it lowers the size asked for
  under the node lock, sends `reclaim`, then resizes the Pod.
- Shared-fleet admission requires a fresh controller grant. CI pressure queues
  immediate idle reclaim; new turns cannot consume a reserved host. See
  [`fleet-sharing.md`](fleet-sharing.md) for grant expiry, allocation ordering,
  resize serialization and rollout requirements.
- A sandbox left running without a residency on a shared node is paused with
  zero additional grace, and its pause queues an immediate shrink. Standalone
  daemons retain configurable idle grace. A residency starting meanwhile
  supersedes the pending pause.
- Sandboxes paused, or errored, for longer than 14 days are deleted by a
  daily job; a session that returns afterwards gets a fresh sandbox.
- The account API lets an account connect an environment (Anthropic
  environment id + environment key, stored encrypted with `Tuist.Vault`),
  list and delete sandboxes, and run commands in a sandbox for validation.

## Measured latency

Production, 7 days to 2026-11-08, from the server's `sandboxes: sandbox
created` and `sandboxes: sandbox resumed` log lines (default 2 vCPU / 4 GiB
shape on the shared OVH Linux fleet):

| Path | n | p50 | p90 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| create from the template snapshot (`boot_ms`) | 79 | 147 ms | 200 ms | 208 ms | 264 ms | 264 ms |
| create from a node-local disk snapshot (cold boot) | 32 | 745 ms | 788 ms | 800 ms | 3.6 s | 3.6 s |
| create from an archive (cold boot, after download) | 6 | 724 ms | 772 ms | | | 772 ms |
| resume on the node (`node_call_ms`) | 266 | 144 ms | 319 ms | 438 ms | 788 ms | 1.3 s |
| resume admission before the node call (`admit_ms`) | 265 | 866 ms | 1.6 s | 1.9 s | 3.1 s | 12.7 s |

The VM is not the bottleneck: half of all resumes spend longer in
`Capacity.admit/1` (grant check, node lock, carve-out growth) than the
node takes to restore. A pause shrinks the carve-out, so nearly every
resume grows it again and waits for the daemon to report the new limit.
The daemon notices within 250 ms, but these numbers predate the change
that cut `Tuist.Sandboxes.NodePresence`'s `broadcast_period` from 1.5 s,
when another replica took up to that long to see the report.
`boot_ms` and `node_call_ms` exclude the API request and Amp's
bootstrap; `admit_ms` is logged only by servers since the field was
added, hence the smaller sample. Reproduce with LogQL quantiles over those
lines (`regexp "admit_ms=(?P<v>\\d+)" | unwrap v`) on
`{namespace="tuist", container="server"}`.

## Not yet

Runner/sandbox capacity policy and rollout gates: [fleet-sharing.md](fleet-sharing.md).

Diff snapshots, userfaultfd restore from object storage, cross-node resume
with memory (archived sandboxes and archived disk snapshots restore on any
node, but cold), per-account egress allowlists, non-root agent execution in the guest, Claude Code
self-hosted runners.

## Operations

The daemon lives in `cmd/sandboxd` with one package per concern under
`internal/`: `firecracker` (API client over the unix socket), `vm` (jailer
spawn, jail file prep, process tracking), `network` (netns, veth, NAT),
`vsock` (guest agent client), `template` (discovery and per-shape snapshot
builds), `sandbox` (lifecycle manager, metadata, metrics, command dispatch),
`server` (WebSocket client), `admin` (bring-up HTTP API), `hostinfo` (cgroup
memory limit and usage, resolvers), `diskusage` (filesystem size and the
exclusive bytes of templates and jails, deduplicated by inode and, on Linux,
by FIEMAP extent sharing so reflink clones count only their deltas), and
`fakevm` (a test double that emulates the Firecracker API and the guest
agent so the manager runs end to end without KVM).

### Deviations from the protocol text above

- Template snapshots are per shape. A Firecracker snapshot fixes the vCPU
  count and memory size, so `rootfs.boot.ext4`, `memfile`, `snapshot`,
  `metadata.json` and `ready` live in
  `/data/sandboxes/templates/<name>/<tag>/shapes/<vcpus>x<memory_mb>/`,
  while `vmlinux` and the pristine `rootfs.ext4` stay in the tag directory.
  A shape is built lazily by the first `create` that needs it (concurrent
  creates wait for the one build) and eagerly at startup for
  `PREBUILD_SHAPES`. `hello.templates[].ready` is true as soon as the kernel
  and rootfs are on the node; `shapes` lists the snapshots already built.
- The guest does not mount the workspace at template time. `create` makes
  `workspace.ext4` as a sparse file of `workspace_gb` (no mkfs on the host)
  and sends `configure {format_workspace: true}` after the restore;
  `resume` sends `configure` without it. The template build attaches a
  sparse workspace of `TEMPLATE_WORKSPACE_GB` (default 10); when a create
  asks for a different size the daemon issues `PATCH /drives/workspace`
  after the load so the guest learns the new capacity before formatting.
  Bazel templates are the exception: the builder formats and unmounts a pristine
  workspace before snapshotting and records `workspace_prepared`. Matching-size
  creates reflink `workspace.empty.ext4` and mount it without formatting; older
  snapshots and different sizes retain the original path. The optional trusted
  `/usr/local/bin/sbx-template-prepare` hook runs before unmounting. Never derive
  this image or memory snapshot from a VM that has received an action or token.

### Configuration (environment)

| Variable | Default | Meaning |
|---|---|---|
| `NODE_NAME` | | Node name for `X-Tuist-Node-Name` (downward API). Required with `SERVER_URL`. |
| `SERVER_URL` | | Server base URL; the daemon dials `/api/internal/sandboxes/nodes/connect`. Empty = admin-only. |
| `TOKEN_PATH` | `/var/run/secrets/tuist/token` | Projected SA token, re-read on every reconnect. |
| `DATA_DIR` | `/data/sandboxes` | Templates under `templates/`, jails under `jail/`. |
| `TEMPLATE_NAME`, `TEMPLATE_TAG` | `default`, discovered | Default template and the tag creates use for it when the caller names none; the tag may be omitted only when exactly one version is on the node. With a tag set and no `EXECUTION_SLOTS`, startup deletes this template's other tags unless a sandbox or disk snapshot on the node records them; the init container seeds a tag per upgrade and they otherwise fill the runner node's data disk. |
| `FIRECRACKER_BIN`, `JAILER_BIN` | `/usr/local/bin/{firecracker,jailer}` | |
| `JAILER_ENABLED` | `true` | `false` runs Firecracker directly under `ip netns exec` with absolute paths (debug only). |
| `JAIL_UID_BASE` | `10000` | Jail uid/gid = base + slot index. |
| `PREBUILD_SHAPES` | | Comma-separated shapes to build at startup, e.g. `2x4096,4x8192`. Must be a subset of `ALLOWED_SHAPES` when that is set. |
| `ALLOWED_SHAPES` | | The only shapes `create` and template builds accept. Empty accepts any valid shape. |
| `DISK_BUDGET_GIB` | `0` | Share of the data filesystem sandboxes may reserve, reported as `disk.budget_bytes`; the server reserves each sandbox's ceiling against it. `0` reports no budget. |
| `DIRECT_EXEC_ADDR` | | Listen address for claims of claimed execs, e.g. `$(POD_IP):7071`. Empty disables claims. |
| `POD_NAME` | | The daemon's Pod (downward API), reported in `hello.elastic` so the server can resize it. |
| `MEMORY_FLOOR_GIB`, `MEMORY_CEILING_GIB` | `0`, `0` | The memory the Pod starts at and the most the server may grow it to, reported in `hello.elastic`. A ceiling not above the floor keeps the limit fixed. |
| `TEMPLATE_WORKSPACE_GB` | `10` | Workspace size attached during the template boot. Shapes built with another size are removed at startup and rebuilt. |
| `BOOT_TIMEOUT`, `TEMPLATE_BOOT_TIMEOUT` | `60s`, `2m` | Agent readiness after a restore / a cold template boot. |
| `SHUTDOWN_TIMEOUT` | `60s` | Budget for stopping workers and pausing every running sandbox on SIGTERM; size the pod's grace period above it. |
| `METRICS_ADDR` | `:9470` | `/metrics` and `/healthz`. |
| `ADMIN_ADDR` | | Unauthenticated bring-up API (staging only, behind NetworkPolicy). |
| `POD_INTERFACE` | default route | Pod egress device for the slot-range MASQUERADE. |
| `DAEMON_ONLY_TCP_PORTS` | | Comma-separated TCP ports the daemon reaches through the pod and the guests may not, on any address: forwarded guest traffic to them is dropped. The chart lists the server Pods' target port (unless `guestServerAccess`) and the in-rack archive store's port when `sandboxes.networkPolicy.archiveStoreEgress` is on. `DAEMON_ONLY_TCP_PORT`, the single port an older chart sets, is still read. |
| `CHECKOUT_AGENT_URL` | | The node's runner-cache agent, e.g. `http://<runner-cache-volumes Service>.tuist-runners.svc.cluster.local:8090`; see "Guest to host: checkout". Needs `POD_NAME`. Empty ignores checkout grants. The chart sets it, and lists 8090 in `DAEMON_ONLY_TCP_PORTS`, when Linux cache volumes are enabled. |
| `CHECKOUT_WORKSPACES_GIB` | `0` | Budget for prepared checkout workspaces under `DATA_DIR/checkouts`, taken out of `DISK_BUDGET_GIB` (the daemon reports the budget less this and the blob cache, and refuses to start unless both fit). Needs `CHECKOUT_AGENT_URL`. `0` disables them. A build also needs free space for four times the budget plus 10 GiB. |
| `CHECKOUT_WORKSPACES_TTL` | `6h` | How long a prepared workspace is used after it is built. |
| `GUESTS_REACH_SERVER` | `false` | With `SERVER_URL` set and this false, the daemon resolves `SERVER_URL` at startup (retrying cluster DNS for a minute) and drops guest traffic to those addresses and port. |
| `LOG_LEVEL` | `info` | slog level. |

### Validation scripts

`validation/` holds the end-to-end checks used during bring-up and after
every image change: `validate-job.sh` runs create, exec, pause, resume and
delete against a node's admin API from a Job in the cluster;
`managed-agents-smoke.sh` runs a two-turn Managed Agents session across a
pause and resume on a connected environment; `managed-agents-chat.sh` is an
interactive terminal session on the same path.

### Admin API

`POST /v1/sandboxes {id?,template,template_tag?,vcpus,memory_mb,workspace_gb,hostname}`
returns `{id, boot_ms}`; `POST /v1/sandboxes/{id}/{pause,resume,delete}`;
`POST /v1/sandboxes/{id}/exec {cmd,env,cwd,timeout_ms}` returns
`{stdout,stderr,exit_code,duration_ms}`; `POST
/v1/sandboxes/{id}/worker/{start,stop}`; `GET /v1/sandboxes`, `GET
/v1/sandboxes/{id}`, `GET /v1/templates`; `POST
/v1/templates/{name}/{tag}/build {vcpus,memory_mb}`.

### Process model

The jailer parent exits as soon as it has forked Firecracker into the new
pid namespace, so the daemon sets itself as child subreaper, reads the pid
from `<jail>/root/firecracker.pid` and reaps that pid itself. Killing a VM
is SIGKILL to the spawn's process group and to that pid. Before every spawn
the daemon removes the previous run's API socket, `v.sock`, `/dev/kvm` and
`/dev/net/tun` from the jail root: Firecracker will not bind over an
existing socket and the jailer's `mknod` fails on an existing node.

Template artifacts are hard-linked into jails (`vmlinux`, `mem`,
`snapshot`) and must stay world-readable; the daemon never chowns a hard
link. The build hands every shape file to root before marking it ready: a
jail uid is a reused slot, so a template file it owned could be rewritten
by a later sandbox in that slot for every sandbox restored after it.
Startup deletes a shape holding any file the daemon does not own, and the
next create rebuilds it instead of trusting its contents. Firecracker
opens the `File` memory backend read-only, so sharing the template memfile
across sandboxes is safe; the first pause replaces the link with the
sandbox's own memory file.

### Startup and recovery

Every jail directory is read back on startup. Since nothing survives a pod
restart, a sandbox recorded as `running` lost its VM. Its disks have moved
on since whatever memory image sits beside them (its last pause, or the
template memfile for generation 0), and Firecracker treats the disks as
part of a snapshot, so that image is never restored: the sandbox becomes
`paused` with `cold_boot` set when its rootfs, workspace and kernel are
present, and `error` otherwise. The next `resume` of a `cold_boot` sandbox
boots the kernel on its own disks instead of loading a snapshot, discards
the stale `mem` and `snapshot`, and clears the flag. For the guest this is a
power cut: processes are gone, data it had flushed survives with its
journals replayed on mount, and writes still in its page cache (up to ext4's
5 s commit interval) are lost;
the next pause writes a fresh pair. A cleanly paused sandbox keeps its
memory image, because the pause path pauses the VM, snapshots, then kills
it, so nothing touches the disks afterwards, unless another Firecracker
version wrote that image (`firecracker_version` in its metadata, empty
before it was recorded): it is set to `cold_boot` too, because this version
cannot load it. The daemon exits at startup when it cannot read its own
Firecracker version. Jail directories without
`metadata.json` (an interrupted create or template build), `*.building`
shape directories, shapes another Firecracker version took or built with a
workspace other than `TEMPLATE_WORKSPACE_GB`, and every `sbx-*` netns are
removed.

On SIGTERM the daemon stops every running worker (SIGTERM, then SIGKILL
after `STOP_WORKER_GRACE`; the SDK worker force-stops its work item and
Anthropic re-queues the session on its next event) and pauses every running
sandbox within `SHUTDOWN_TIMEOUT`, so a rollout restores memory rather than
cold booting, except one that changes the Firecracker version. Whatever is still running at the deadline takes the cold-boot
path on recovery.

Server deployments publish the daemon image as `sha-<commit>` of the last
commit that changed `infra/sandboxd` (outside its Markdown) or its publisher,
so other deploys leave the DaemonSet untouched; a server-only re-promotion
keeps the live daemon. The values-file tags only seed a first install.

Lifecycle commands (`create`, `resume`, `pause`, `delete`) run detached
from the WebSocket that delivered them, with their own timeouts, so a
dropped connection cannot abort a snapshot half-way; `exec` is cancelled
with the connection (its output has nowhere to go), which kills the guest
process. Events that cannot be delivered are queued (bounded) for the next
connection. The read loop does not wait for in-flight commands when a
connection ends, so a long snapshot or template build never keeps the node
from reconnecting or from draining on shutdown; a result that outlives its
connection is sent on the next one, where the server drops the unknown id.

The guest is untrusted (root inside the VM can replace the agent), so the
daemon bounds what it takes from it: a vsock frame is at most 4 MiB, exec
output past 2 MiB is not streamed to the server, worker output is logged at
most 5000 lines of 4 KiB, and the console log is capped as above. Files in
the jail root, which belongs to the jailed Firecracker's uid, are never
opened through a symlink, and console output never travels to the server
inside an error.

### Metrics

`sandboxd_create_seconds`, `sandboxd_resume_seconds`,
`sandboxd_pause_seconds`, `sandboxd_template_build_seconds{shape}`
(histograms), `sandboxd_sandboxes{state}`, `sandboxd_workers_running`
(gauges), `sandboxd_operations_total{op,result}` (counter).
`sandboxd_lifecycle_phase_seconds{phase}` breaks down fixed lifecycle phases;
`sandboxd_blob_cache_requests_total{result}`, `sandboxd_blob_cache_fetched_bytes_total` and `sandboxd_blob_cache_bytes` cover the blob cache. sandbox IDs are never labels. Delete overlaps process exit and network teardown,
but retains files, the instance reference and slot until both succeed.

### Development

The module is in the root `go.work`; use `GOWORK=off` to test its standalone
dependency graph. `go test ./...` runs on macOS: the
Linux-only syscalls (FICLONE, wait4, prctl) sit behind build tags with
stubs, and `internal/fakevm` stands in for Firecracker. Fake-VM fixtures
inject a small file copy so lifecycle tests also run on Linux filesystems
without reflinks. Production defaults to strict `vm.Reflink`; its file test
checks clone isolation on supporting filesystems and rejection without a
copy fallback on unsupported ones. Anything that
needs KVM (a real boot, the jailer, tap devices) can only be exercised on
a node, ideally through `ADMIN_ADDR` on staging.
