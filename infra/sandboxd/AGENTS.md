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
a separate substrate on the same nodes.

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
  run/firecracker.socket, v.sock, firecracker.log
  metadata.json       {id, template, tag, vcpus, memory_mb, state, generation}
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

## Sandbox lifecycle on the node

- `create {sandbox_id, template, vcpus, memory_mb, workspace_gb, hostname}`:
  make the jail dir, hard link `vmlinux` and `mem`, reflink `rootfs.ext4`,
  create a sparse unformatted `workspace.ext4`, set up the network namespace,
  spawn the jailer + Firecracker, `PUT /snapshot/load` with the shape's
  vmstate and the `File` memory backend (`resume_vm: true`), then over vsock
  `set_time`, `configure {hostname, dns, format_workspace: true}` (the guest
  flushes the block device's cached sectors, formats `/dev/vdb` and mounts it
  at `/workspace`) and `ping`. Reports `boot_ms`.
- `pause {sandbox_id}`: refuse if a worker or exec is still running. `PATCH
  /vm Paused`, `PUT /snapshot/create` (Full) into `mem.new` + `snapshot.new`,
  kill Firecracker, rename over `mem` and `snapshot`, tear down the netns.
  Reports `snapshot_ms` and `mem_bytes`.
- `resume {sandbox_id}`: recreate the netns with the same tap name and
  addresses, spawn jailer + Firecracker, `PUT /snapshot/load` with the
  sandbox's own `mem` (`File` backend, `resume_vm: true`), then `set_time`,
  `configure` (flushes ARP) and `ping`. Reports `restore_ms`.
- `delete {sandbox_id}`: kill the VM if running, tear down the netns, remove
  the jail dir.
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
 "templates":[{"name":"default","tag":"sha-...","ready":true}],
 "sandboxes":[{"id":"...","state":"running","template":"default","template_tag":"...",
               "vcpus":2,"memory_mb":4096,"worker_running":false}]}
{"type":"result","id":"c1","ok":true,"data":{...}}
{"type":"result","id":"c1","ok":false,"error":"..."}
{"type":"stream","id":"c1","stream":"stdout","data_b64":"..."}
{"type":"event","event":"worker_exited","sandbox_id":"...","exit_code":0,"duration_ms":1234}
{"type":"event","event":"sandbox_died","sandbox_id":"...","reason":"..."}
{"type":"event","event":"template_ready","name":"default","tag":"..."}
{"type":"report","sandboxes":[...same shape as hello...],"memory":{"used_bytes":N}}
```

Server to node:

```
{"type":"command","id":"c1","op":"create","args":{"sandbox_id":"...","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":10,"hostname":"sbx-abc"}}
{"type":"command","id":"c2","op":"resume","args":{"sandbox_id":"..."}}
{"type":"command","id":"c3","op":"pause","args":{"sandbox_id":"..."}}
{"type":"command","id":"c4","op":"delete","args":{"sandbox_id":"..."}}
{"type":"command","id":"c5","op":"exec","args":{"sandbox_id":"...","cmd":["/bin/bash","-lc","ls"],"env":{},"cwd":"/workspace","timeout_ms":60000}}
{"type":"command","id":"c6","op":"start_worker","args":{"sandbox_id":"...","env":{"ANTHROPIC_SESSION_ID":"...","ANTHROPIC_WORK_ID":"...","ANTHROPIC_ENVIRONMENT_ID":"...","ANTHROPIC_ENVIRONMENT_KEY":"...","ANTHROPIC_WORK_SECRET":"...","ANTHROPIC_BASE_URL":"...","SBX_MAX_IDLE":"30s"}}}
{"type":"command","id":"c7","op":"stop_worker","args":{"sandbox_id":"..."}}
{"type":"command","id":"c8","op":"status","args":{"sandbox_id":"..."}}
```

Every command gets exactly one `result`. `exec` emits `stream` frames before
its result (`data.exit_code`). `start_worker` results as soon as the worker
process is running; `worker_exited` follows as an event. Credentials travel
only in `start_worker` args, are handed to the guest over vsock, and are never
written to the node's disk by the daemon.

## Worker inside the guest

`sbx-worker` wraps the Anthropic Go SDK's `EnvironmentWorker.HandleItem`
with `Workdir=/workspace` and `MaxIdle` from `SBX_MAX_IDLE` (default 30s). It
reads `ANTHROPIC_SESSION_ID`, `ANTHROPIC_WORK_ID`, `ANTHROPIC_ENVIRONMENT_ID`,
`ANTHROPIC_ENVIRONMENT_KEY`, `ANTHROPIC_WORK_SECRET` and optionally
`ANTHROPIC_BASE_URL` from its environment, heartbeats the work-item lease,
attaches to the session's event stream, executes tool calls and exits after
`MaxIdle` following an `end_turn` idle. The work item was already claimed and
acknowledged by the server's poller; the worker never polls.

## Server side

- A poller process per connected Anthropic environment long-polls the work
  queue, acknowledges session items immediately, force-stops anything that is
  not a session, and hands the item to the router.
- The router finds the sandbox for `data.id` (the session) or creates one from
  the environment's template and shape, resumes it if paused, and sends
  `start_worker`.
- `worker_exited` ends the residency; the sandbox is paused after a grace
  period (default 30s) unless a new residency started meanwhile.
- The account API lets an account connect an environment (Anthropic
  environment id + environment key, stored encrypted with `Tuist.Vault`),
  list and delete sandboxes, and run commands in a sandbox for validation.

## Not yet

Diff snapshots, userfaultfd restore from object storage, cross-node resume,
per-account egress policy, memory overcommit admission, non-root execution in
the guest, Claude Code self-hosted runners.

## Operations

The daemon lives in `cmd/sandboxd` with one package per concern under
`internal/`: `firecracker` (API client over the unix socket), `vm` (jailer
spawn, jail file prep, process tracking), `network` (netns, veth, NAT),
`vsock` (guest agent client), `template` (discovery and per-shape snapshot
builds), `sandbox` (lifecycle manager, metadata, metrics, command dispatch),
`server` (WebSocket client), `admin` (bring-up HTTP API), `hostinfo`, and
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

### Configuration (environment)

| Variable | Default | Meaning |
|---|---|---|
| `NODE_NAME` | | Node name for `X-Tuist-Node-Name` (downward API). Required with `SERVER_URL`. |
| `SERVER_URL` | | Server base URL; the daemon dials `/api/internal/sandboxes/nodes/connect`. Empty = admin-only. |
| `TOKEN_PATH` | `/var/run/secrets/tuist/token` | Projected SA token, re-read on every reconnect. |
| `DATA_DIR` | `/data/sandboxes` | Templates under `templates/`, jails under `jail/`. |
| `TEMPLATE_NAME`, `TEMPLATE_TAG` | `default`, discovered | Default template; the tag may be omitted when exactly one is present. |
| `FIRECRACKER_BIN`, `JAILER_BIN` | `/usr/local/bin/{firecracker,jailer}` | |
| `JAILER_ENABLED` | `true` | `false` runs Firecracker directly under `ip netns exec` with absolute paths (debug only). |
| `JAIL_UID_BASE` | `10000` | Jail uid/gid = base + slot index. |
| `PREBUILD_SHAPES` | | Comma-separated shapes to build at startup, e.g. `2x4096,4x8192`. |
| `TEMPLATE_WORKSPACE_GB` | `10` | Workspace size attached during the template boot. |
| `BOOT_TIMEOUT`, `TEMPLATE_BOOT_TIMEOUT` | `60s`, `2m` | Agent readiness after a restore / a cold template boot. |
| `SHUTDOWN_TIMEOUT` | `60s` | Budget for pausing idle sandboxes on SIGTERM; size the pod's grace period above it. |
| `METRICS_ADDR` | `:9470` | `/metrics` and `/healthz`. |
| `ADMIN_ADDR` | | Unauthenticated bring-up API (staging only, behind NetworkPolicy). |
| `POD_INTERFACE` | default route | Pod egress device for the slot-range MASQUERADE. |
| `LOG_LEVEL` | `info` | slog level. |

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
link. Firecracker opens the `File` memory backend read-only, so sharing the
template memfile across sandboxes is safe; the first pause replaces the
link with the sandbox's own memory file.

### Startup and recovery

Every jail directory is read back on startup. Since nothing survives a pod
restart, a sandbox recorded as `running` becomes `paused` when its `mem`
and `snapshot` exist (that snapshot is its last pause, or the template
snapshot for generation 0; writes the guest made after it to the rootfs
are then visible to a restored memory image that does not know about
them) and `error` otherwise. Jail directories without `metadata.json` (an
interrupted create or template build), `*.building` shape directories and
every `sbx-*` netns are removed.

Lifecycle commands (`create`, `resume`, `pause`, `delete`) run detached
from the WebSocket that delivered them, with their own timeouts, so a
dropped connection cannot abort a snapshot half-way; `exec` is cancelled
with the connection (its output has nowhere to go), which kills the guest
process. Events that cannot be delivered are queued (bounded) for the next
connection.

### Metrics

`sandboxd_create_seconds`, `sandboxd_resume_seconds`,
`sandboxd_pause_seconds`, `sandboxd_template_build_seconds{shape}`
(histograms), `sandboxd_sandboxes{state}`, `sandboxd_workers_running`
(gauges), `sandboxd_operations_total{op,result}` (counter).

### Development

The module is not in the root `go.work`; run with `GOWORK=off` (or add it
with `go work use ./infra/sandboxd`). `go test ./...` runs on macOS: the
Linux-only syscalls (FICLONE, wait4, prctl) sit behind build tags with
stubs, and `internal/fakevm` stands in for Firecracker. Anything that
needs KVM (a real boot, the jailer, tap devices) can only be exercised on
a node, ideally through `ADMIN_ADDR` on staging.
