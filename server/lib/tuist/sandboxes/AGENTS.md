# Sandboxes (Context)

Server control plane for the Firecracker sandboxes run by `sandboxd`
(`infra/sandboxd/AGENTS.md` is the protocol and lifecycle spec). One
sandbox is one persistent microVM per coding-agent session; the first
consumer is Claude Managed Agents `self_hosted` environments.

Linux REAPI actions use a separate `Tuist.RemoteExecution` lifecycle and
`sandboxes.purpose = remote_execution`. Keep them out of agent listing, quotas,
idle retention and node-report reconciliation: their scheduler and lease own
them. Reserved executor nodes must not admit agent sessions; execution rows and
resource reservations survive errors until acknowledged VM deletion. An executor
on a shared runner host connects as `<node>.remote-execution` with its own
carve-out: execution placement uses memory its Pod holds without a grant and may
grow past the grant's bytes, but never past a revoked or expired grant. Agent
admission keeps requiring the grant.
See [the rollout and recovery contract](../../../../infra/sandbox-image/remote-execution.md).

## Pieces

- `Tuist.Sandboxes`: context over `sandboxes`,
  `sandbox_agent_environments` and `sandbox_agent_sessions`; every state
  transition maps to one node command (`create`, `resume`, `pause`,
  `delete`, `exec`, `start_worker`). `handle_node_event/2` and
  `reconcile_node_report/2` absorb what the node reports back. The
  agent-session functions are delegated to `Tuist.Sandboxes.AgentSessions`.
- `Tuist.Sandboxes.AgentSessions`: starts Managed Agents sessions on an
  account's environment with the environment's `anthropic_api_key`
  (`start_agent_session/3`), and follows them (`refresh_agent_session/1`,
  `list_agent_session_events/2`, `send_agent_session_message/2`,
  `archive_agent_session/1`). Event listing follows Anthropic's pages
  (1000 events each, at most 20 pages per call) and hands out an opaque
  cursor, the base64url of `"<processed_at>|<event_id>"` of the last
  event returned; a listing with a cursor asks Anthropic for
  `created_at[gte]=<processed_at>` and drops everything up to and
  including the event id, so events sharing a timestamp are neither
  lost nor repeated. A listing that stops at the page cap with pages
  left hands out `"<bound>|<event_id>|<page>"` instead, so the next call
  continues the same listing from Anthropic's next page. `next_after` is
  nil only while the session has no events. The agent is created on first use with the
  environment's `agent_model` and `agent_system_prompt` and cached in
  `anthropic_agent_id`; a per-session `model` override gets an uncached
  agent, and `agent_id` runs an existing one. The row id is generated
  before the Anthropic call and travels in the session `metadata`
  (`tuist_agent_session_id`, `repository_url`, `repository_ref`).
- `Tuist.Sandboxes.Capacity`: memory and disk admission. Charges every
  creating, resuming or running sandbox with its guest memory plus a
  64 MiB VMM overhead against the node's reported cgroup limit less a
  512 MiB daemon reserve; `place/1` reserves the ready node with the most
  free memory (setting `node_name` under a per-node advisory lock) and
  `admit/1` reserves the paused sandbox's own node by moving the row to
  `resuming`. When nothing fits, idle running sandboxes (no residency)
  are paused, longest idle first. Disk is reserved at each sandbox's
  ceiling (the template's `rootfs_bytes`, `workspace_gb` and the memory
  image, all fixed-size files, plus 64 MiB): a new sandbox only goes to a
  node whose disk budget holds its ceiling on top of the ceilings of the
  rows placed there (creating, running, resuming, paused) and of errored
  rows whose jail the node still reports, checked under the node's lock.
  Rows decide rather than the report, which lags: a delete frees its
  reservation at once. A paused sandbox's disk is already
  reserved, so a resume only needs room for its next pause on the
  filesystem. `admissible?/2` is the check the poller runs before
  acknowledging a work item. A node that reports no capacity or no disk
  budget is not budgeted on that resource.
- Elastic carve-outs (`Capacity.grow/3`, `Capacity.shrink/1`): a node whose
  daemon reports `elastic` with a ceiling above its floor is grown in place
  when nothing fits after pausing idle sandboxes, in whole GiB up to the
  ceiling, through `Tuist.Kubernetes.Client.resize_sandbox_daemon_memory/3`
  (the server SA holds `pods/resize` in the sandboxes namespace). The size
  asked for is a `Tuist.Sandboxes.SandboxNode` row (`sandbox_nodes`) keyed by
  node and pod name; placements budget against the smaller of it and the
  reported limit, so a growth is only used once the daemon reports it and a
  shrink stops placements first. A growth the kubelet defers (read from the
  Pod's `PodResizePending` condition) is given back and the next node tried;
  only the last deferral stays asked for. `admissible?/2` asks for a growth
  and admits the item once the kubelet has applied it, within 2.5 s, which
  keeps the poller inside the queue's 5 s acknowledgement; otherwise the item
  stays queued. The chart's floor is 1 GiB, so every node's first sandbox
  grows its carve-out. `Tuist.Sandboxes.Workers.ShrinkCarveOutsWorker` (every
  minute) shrinks carve-outs back toward what their running sandboxes hold,
  never below the floor, retaining an in-flight growth for at most 15 seconds,
  sending the daemon `reclaim` before the resize because the kubelet refuses
  to lower a limit below current usage; it also retries a shrink the kubelet
  has not applied and cancels a deferred growth no longer needed.
- `Tuist.Sandboxes.Nodes`: cluster-wide view of the connected nodes
  (`connected_nodes/0`) read from
  `Tuist.Sandboxes.NodePresence`, a `Phoenix.Presence` on `Tuist.PubSub`
  keyed by node name under `"sandbox_nodes"` with the socket pid,
  Erlang node, capacity, templates and sandboxes as meta, and `call/4`,
  the blocking request/response bridge onto `TuistWeb.SandboxNodeWebSock`
  that broadcasts the command on `"sandbox_node:<name>"` and monitors
  the socket pid, with `on_stream` for `exec` output.
- `Tuist.Sandboxes.Anthropic.Client`: Req client for the work queue
  (`poll`, `ack`, `stop`, `stats`), authenticated with the environment
  key. `TUIST_ANTHROPIC_API_URL` overrides the base URL.
- `Tuist.Sandboxes.Anthropic.ControlPlane`: Req client for `/v1/agents`
  and `/v1/sessions` (`create_agent`, `create_session`, `get_session`,
  `list_events`, `send_message`, `archive_session`), authenticated with
  `x-api-key`. `list_events` fetches one page (`limit`, `order`, `page`,
  `created_at_gte` / `created_at_gt`) and returns `%{data, next_page}`.
  Non-2xx answers become `{:error, %{status, message}}`.
- `Tuist.Sandboxes.Anthropic.Supervisor`: task supervisor + dynamic
  supervisor of the `Poller`s this replica started (one per enabled
  agent environment across the cluster, registered as
  `{:global, {Poller, agent_environment_id}}`), kept in sync with the
  table by `Manager` every 30s. Started on web pods outside tests
  (`sandboxes_children/0` in `Tuist.Application`).
- `Router.session_environment/2` decides the OS a session runs on, for
  the poller's admission and the router alike: an existing sandbox keeps
  its platform; a new one takes the `AgentSession` row's `platform`, else
  the `tuist_platform` session metadata key (`linux`, `darwin`, `macos`),
  else the environment's. A platform other than the environment's runs
  that platform's default template and shape (`Sandboxes.platform_defaults/1`).
- `Tuist.Sandboxes.Router`: finds or creates the session's sandbox,
  resumes it and records the residency in one step
  (`Sandboxes.prepare_residency/2`), then starts `sbx-worker` with the
  session credentials; force-stops the work item on any failure so
  Anthropic re-queues it. Like an Amp Orb's spawn, a turn that just
  created a macOS sandbox records its residency without a fresh CI grant
  (`created: true`): the VM already holds its slot. Inside the residency
  that created the sandbox, the router binds it to the `AgentSession` row
  (looked up by `anthropic_session_id`) and clones the requested
  repository into `<workspace>/<name>` (`/workspace` on Linux,
  `/Users/runner/work` on macOS) with `git clone --filter=blob:none` (branch via
  `--branch`, a commit sha via a follow-up `checkout`; 90s budget). A
  github.com repository named on the `AgentSession` row is cloned with a
  token minted for that one repository with `contents: read`
  (`GitHub.App.create_scoped_installation_token/4`), passed to git as
  an `http.extraheader` through `GIT_CONFIG_*` environment variables so
  it never lands in `.git/config`. A repository named only in the
  session metadata (which anyone with access to the Anthropic workspace
  can set) is cloned anonymously. A failed clone is logged and the
  worker still starts.
- Claude Code cloud environments (`kind: :claude_code`, `ccpool_...`) are
  agent environments the Managed Agents `Manager` skips. Users pick the OS
  by picking the environment in Claude Code, so each runs its own platform.
  `ClaudeCodeReconciler` (Oban cron, every minute, and on create/delete)
  keeps one orchestrator Deployment per enabled environment
  (`ClaudeCodeRuntime`, `infra/claude-code-runners`) in the Amp provider
  namespace. Its spawn hook calls `ClaudeCodeRunnersController` with a
  projected token (audience `tuist-claude-code-runners`) that names the
  environment. `ClaudeCodeRunners.spawn/2` answers before the VM boots:
  `:running` when the session's sandbox holds a residency, `:accepted` after
  `Capacity.admissible?/2`, else `:no_capacity`. A supervised task then, under
  the `claude-code:<env>:<session>` lock (`wait: false`), finds or creates
  the sandbox, records the residency with `created:` like the router, and
  starts `sbx-worker` with `SBX_CLAUDE_CODE_WORK_ORDER`. The work order is
  the runner's credential: keep it out of rows and logs.
- `Tuist.Sandboxes.Workers.PauseSandboxWorker`: Oban job scheduled by
  `end_residency/1`; `Sandboxes.pause_idle/2` pauses only when the
  sandbox is still running, has no residency and the epoch it was
  enqueued with is still current, checked under the sandbox's lock.
- `Tuist.Sandboxes.DiskSnapshots`: disk snapshots (`sandbox_disk_snapshots`)
  of paused Amp Orbs, saved on the Orb's node by `save_disks` after a pause
  with `sync_disks` and keyed by account and Amp's `snapshot_id`. A new Orb
  spawned with that id goes to the snapshot's node (`Capacity.place_on_node/2`)
  and is created with `from_disk_snapshot`; when that node cannot take it or
  the clone fails, it boots the template instead. Each snapshot reserves its
  rootfs and workspace ceiling in `Capacity.reserved_disk_bytes/1`, and the
  save itself is admitted under the node's lock
  (`Capacity.reserve_disk_snapshot/3`). A newer save replaces older copies
  of the same id, and of the id the saving Orb was spawned from
  (`sandboxes.amp_base_snapshot_id`), since Amp refreshes a project snapshot
  under a new id. Node reports reconcile them like sandboxes: copies no row
  knows are deleted from the node, rows whose copy the node no longer lists
  are dropped after a two-minute grace. A daemon that reports no
  `disk_snapshots` key is left alone.
  `Tuist.Sandboxes.Workers.DiskSnapshotRetentionWorker` (hourly) deletes
  snapshots unused for 72 hours and saves stuck for 15 minutes.
- `Tuist.Sandboxes.Archives`: the archive tier of paused Amp Orbs. An Orb
  paused longer than `Environment.sandbox_archive_after_hours/0` (off when
  unset), or the least recently paused one of an account whose disk quota
  refused a create or restore (`make_room/1`), is uploaded by its node (`archive` command with presigned multipart
  part URLs; the daemon holds no storage credentials) as kernel, rootfs and
  workspace without the memory image, to `sandbox-archives/<account_id>/`
  in the archive bucket of the in-rack store at the node's site (a shard
  storage target with an `archive_bucket`, recorded in `archive_store`), or
  in the account's storage when there is none or the account has its own
  S3 storage. The sandboxd NetworkPolicy lets the daemon reach the store
  and the daemon drops guest traffic to its port. The row
  becomes `archived` with `node_name` nil only after the upload is
  completed and readable, then the jail is deleted; an `archived` row a node
  still reports is deleted from it. The upload runs without the sandbox
  lock (taken only to start and to finish), so a resume wins: the node
  cancels the upload and `finish` discards one whose row changed. A spawn
  of an archived Orb (`running_or_resume/1`) is admitted like a create
  (the CPU, memory and disk quota), placed by
  `Capacity.place/1`, or by `place/2` among the nodes at its store's site,
  created
  with `from_archive` and cold boots; a failed restore reverts the row to
  `archived`, never to `error`, because the object is the only copy. The
  object is deleted once the restored sandbox runs (`delete_restored/1`),
  with the sandbox, or with the account. `archived` rows are outside every
  node reservation and both limits; accounts stop archiving at 100 GiB of
  archives. There is no count of paused Orbs per account.
  `Tuist.Sandboxes.Workers.ArchiveSandboxesWorker` (hourly) runs
  `Archives.run/0`, which also aborts uploads abandoned for 45 minutes and
  reverts restores stuck for 15.
- Account limits (`Tuist.Sandboxes.Concurrency`), never a count: running
  sandboxes (creating, running or resuming) charge the CPU and memory quota
  (`:sandbox_concurrency_limit`, checked on create, restore and resume,
  retryable), and every sandbox on a node, paused included, charges the disk
  quota (`sandbox_disk_gb_limit`) with its workspace and memory image,
  checked on create and restore only, so lowering it never strands a paused
  sandbox. Past the disk quota, `Archives.make_room/1` queues the archive of
  the account's least recently paused idle Orb and the refusal is retryable
  (`:sandbox_disk_limit`); when nothing can be archived it is final
  (`:sandbox_limit`).
- Idle Orbs: node reports carry each running VM's `cpu_ms`. A reading more
  than 20 ms per second above `guest_cpu_ms` since `last_active_at`, or
  below it (a new VM process), records activity. A running Orb quiet for
  ten minutes enqueues `Tuist.Sandboxes.Workers.PauseIdleOrbWorker`, which
  calls `AmpOrbs.pause_idle/2`: under the Orb's dispatch lock, it pauses
  only if `last_active_at` is unchanged, the same way Amp's pause does.
  Without `cpu_ms` (an older daemon), `guest_cpu_ms` stays nil and nothing
  is paused.
- `Tuist.Sandboxes.Workers.RetentionWorker`: daily cron (shared crons in
  `Tuist.Oban.RuntimeConfig`) that deletes sandboxes paused, or errored,
  for longer than 14 days (both still hold their disk), falling back to
  the row's last update when the node paused the sandbox without the
  server recording `paused_at`.
- Idle pauses: a create, a resume or an exec that leaves a sandbox
  running without a residency (re)schedules `PauseSandboxWorker` after
  the grace period with the current epoch, so API-driven sandboxes are
  paused once idle like agent ones; a residency starting meanwhile bumps
  the epoch and the pending job does nothing.

Shared-fleet admission requires a fresh controller allocation on `sandbox_nodes`.
CI reservation revocation, zero extra warm memory, timestamp ordering and resize
serialization are specified in [`fleet-sharing.md`](../../../../infra/sandboxd/fleet-sharing.md).
`ReclaimCapacityWorker` applies pressure after the allocation is committed.
Shared-node idle pauses have zero grace and enqueue shrink work; active
residencies and daemon worker/exec guards remain authoritative.

Account compute admission is independent of CI: `Tuist.Sandboxes.Concurrency`
charges creating, resuming and running rows against account vCPU/RAM limits.
Create and resume must reserve quota in the same transaction as their state
transition, under the account row lock. Never hold that lock across node or
Kubernetes calls. Ops can adjust the limits; public account changesets must not
cast them. Pauses release compute quota, not the existing live-sandbox/disk limit.

## Multiple replicas

Managed Amp Orbs use account-owned integrations and a workload-authenticated internal dispatch endpoint; standalone providers retain the account-admin endpoint. Both use the `AmpOrbs` context;
[`infra/amp-orbs/README.md`](../../../../infra/amp-orbs/README.md) specifies
the provider contract and rollout. Preserve their active residency while
bootstrap is detached, and exclude non-null `amp_orb_id` rows from inactivity
retention: Amp owns their pause/delete lifecycle.

Web replicas form an Erlang cluster, and nothing here assumes the
socket, the poller and the caller share a replica:

- A node's socket lands on one replica and tracks itself in
  `NodePresence`; `connected_nodes/0`, `Capacity.ready_nodes/1` and
  `Nodes.call/4` read presence, so `Router.dispatch` and
  `PauseSandboxWorker` work from any replica. A node with two presences
  (a reconnect racing its old socket) counts by the newest
  `connected_at`; the new socket's `hello` broadcasts
  `:sandbox_node_superseded` on the node topic and the old socket
  untracks and closes.
- Commands travel over `Tuist.PubSub`: the socket subscribes to
  `"sandbox_node:<name>"` on `hello`, `Nodes.call/4` broadcasts
  `{:sandbox_command, ref, op, args, from}` there and the socket answers
  `from` directly. A socket forwards a command only while presence names
  it as the node's current socket, so a command broadcast in the moment
  between a reconnect and the old socket's exit runs once. The caller monitors the socket pid from the presence
  meta, so a socket dying mid-call yields `{:error, :node_disconnected}`
  wherever the caller runs.
- A replica that has just started takes traffic a few seconds before
  it has joined the cluster and received the node presences, and a node
  that has just reconnected is invisible while it does. `Nodes.call/4`,
  placement and resume admission therefore wait up to 10 s
  (`Nodes.presence_wait_ms/0`) for a node to become visible before
  answering `:not_connected` or `:no_node`; the poller's admission check
  does not wait. `NodePresence` heartbeats every 3 s when idle (the
  tracker default is 15 s) so a new replica discovers its peers well
  inside that wait.
- Each environment has one poller in the cluster, held under a
  `:global` name. Every replica's `Manager` asks its dynamic supervisor
  to start every enabled environment's poller each reconcile;
  `already_started` means another replica has it, and the reconcile of
  a surviving replica restarts the pollers of one that died. Pollers of
  removed or disabled environments are stopped by pid wherever they
  run.

## Invariants

- The sandbox row exists before the node hears its id, so a node report
  that races a create never looks like an orphan. Ids a node reports
  that the database does not know are deleted from the node.
- Lifecycle transitions of one sandbox (resume, pause, the resume plus
  residency of a new turn, delete) run under its cluster-wide `:global`
  lock (`Sandboxes.with_sandbox_lock/3`) against a freshly read row. A
  reclaim runs under the lock of the sandbox it makes room for, so it
  only takes other sandboxes' locks with `wait: false` and skips busy
  ones; nothing waits on two locks. The node's socket process never
  takes a lock (node commands issued under one are answered through
  it), so changes it makes (`worker_exited`, `sandbox_died`, reports)
  are single SQL updates guarded by the state they were read in.
- `residency_epoch` increments on every residency start and end, in
  SQL; it is what makes a scheduled pause safe to leave enqueued.
- A row left `creating` or `resuming` by a caller that died (a web pod
  stopped mid-operation) is settled by the node's next report once it
  has been stuck for 150 s: a `resuming` row takes the state the node
  reports, a `creating` row the node does not list becomes `error`. A
  node reporting a sandbox in `error` errors the row with its reason.
- `environment_key` is `Tuist.Vault.Binary` encrypted and never
  serialized by the API. It travels only inside `start_worker` args.
- `anthropic_api_key` is `Tuist.Vault.Binary` encrypted, never
  serialized by the API (`has_api_key` is), and only ever used
  server-side by `ControlPlane`. Installation tokens used for private
  clones live only in the clone command's environment; git output is
  redacted before it is logged.
- Exec output is capped at 1 MiB per stream as frames arrive (the node
  stops streaming past 2 MiB) and returned with invalid UTF-8 replaced.
- `Tuist.Sandboxes.Commands` (`/:sandbox_id/commands`) runs commands that
  outlive a request: one exec launches the command detached under
  `setsid`, outside the node's exec process-group fence, with its output,
  stdin, pid and exit code in `$HOME/.cache/tuist/commands/<id>` in the
  guest. A `sandbox_commands` row records each command (never its env).
  All commands share the residency `commands` (`begin_shared_residency/2`,
  plus a macOS host hold of the same name), so a sandbox runs several at
  once but an agent turn refuses them with `:busy`. `release_if_idle/1`
  ends it under the sandbox row lock once no row is `running`; `start/2`
  inserts its row before holding, which closes the race with a release.
  `pause_idle/2` skips a sandbox with running commands. `CommandWatchWorker`
  kills each command at its deadline and records commands no client reads.
  The logs endpoint streams ND-JSON by looping `read/3` with 25 s waits,
  under proxy idle timeouts. Never end the residency with
  `end_residency/1`; use `end_residency/2`, which leaves a newer one alone.
- `anthropic_agent_id` is only cached for the environment's own
  `agent_model`; `AgentEnvironment.update_changeset/2` clears it when
  the model or the system prompt changes.
- `Nodes.call/4` must never run on the socket process itself (it waits
  on a message that process has to deliver); report handling spawns
  orphan deletes via `Tuist.Tasks.run_async/1`.

## Web layer

- `TuistWeb.SandboxNodesController` (`GET /api/internal/sandboxes/nodes/connect`):
  TokenReview with the `tuist-sandboxes` audience, namespace check,
  `X-Tuist-Node-Name` that must equal the node the token's pod is bound
  to, WebSocket upgrade to `TuistWeb.SandboxNodeWebSock` with a 120 s
  idle timeout (nodes report every 30 s).
- `TuistWeb.Plugs.RequireSandboxesPlug` gates both account APIs on
  `FeatureFlags.sandboxes_enabled?/1` (an explicit `:sandboxes` flag on
  canary and production), and the poller manager only runs pollers for
  flagged accounts. Accounts get the shapes in `Sandbox.shapes/0` and
  workspaces up to 100 GB.
- `TuistWeb.API.SandboxesController`: API under
  `/api/accounts/:account_handle/sandboxes` (agent environments,
  including `PATCH agent-environments/:id` for the API key, model and
  system prompt; sandboxes, exec, commands, pause/resume/delete). Members
  (`:sandboxes_use`) reach sandboxes, exec and commands, but only on
  sandboxes without an agent environment, Amp integration, provider
  environment or remote-execution purpose; everything else is admin-only.
- Dashboard: `TuistWeb.SandboxesLive` (`/:account_handle/sandboxes`),
  `SandboxInstancesLive` (`/sandboxes/instances`) and `SandboxLive`
  (`/sandboxes/:sandbox_id`) raise `NotFoundError` unless the flag is on and
  `:sandboxes_read` allows the user; the sidebar entry uses the same gate.
  Pause, resume, archive and delete require `:sandboxes_update` (admins), are
  rechecked per event and run in `start_async`, since node commands block.
  Pause goes through `pause_idle/2`, so it never interrupts an agent turn,
  and Amp Orbs are not resumed or restored from the dashboard (Amp does it).
  Archive (`Sandboxes.archive/1`) only queues `ArchiveSandboxesWorker` for
  one paused sandbox of any source, under the account's archive storage cap,
  because the upload outlives a page. The app layout renders no flashes, so
  these pages render theirs with `SandboxesLive.flash_alerts/1`.
  The overview charts come from `Analytics` over ClickHouse
  `sandbox_events`, which `Events` writes on every state change: through
  `update_sandbox/3`, and explicitly where a state is written another way
  (create, delete, `mark_error`, `Archives`). A new state write must record
  its event too, or sessions and concurrency drift. Peak disk follows
  `Concurrency`'s disk charge: a sandbox holds its workspace and memory image
  from `created` (or a restore's `started`) until `archived`, `failed` or
  `deleted`, paused or not. `boot/2` times each
  boot (create or restore) and tags its `started` event with what it booted
  from. Before every Amp pause, `AmpOrbs` reads the birth and modification
  times of Amp's `setup.log` in the guest (`Sandboxes.exec_running/3`, which
  neither resumes nor counts as activity) and records a `setup` event dated
  when setup finished; a log older than the row came with a disk snapshot
  and is ignored. The Setup and Time to start widgets chart those
  durations; vCPU-hours (`Analytics.compute/2`) are on the Usage page,
  priced by `Sandboxes.Pricing` at one rate per vCPU-hour, memory and disk
  included. There is no Stripe meter yet: early access covers the whole
  charge and Billed stays $0 until one exists.
- `TuistWeb.API.AgentSessionsController`: account-admin API under
  `/api/accounts/:account_handle/sandboxes/agent-sessions` (create,
  list, show with live status and usage, `messages`,
  `events?after=<cursor>`, `archive`).
- `Sandboxes.Query` is the public boundary the sandbox API
  (`TuistWeb.API.SandboxesController`: list, show, analytics, pause,
  resume, archive, delete), the MCP sandbox tools and `tuist sandbox` share,
  with contracts in `Sandboxes.Schemas`; keep both exported from `Tuist`.
  It account-scopes every lookup, serializes the dashboard status, and maps
  errors to one HTTP status and message (`Query.error/1`). The API sends
  every 503 with a `retry-after` longer than the CLI's retry budget: the
  server has already waited for the node, so replays only repeat the wait.
  Every caller
  requires an account administrator and the sandboxes flag, read-only
  calls included, because sandboxes run arbitrary commands. MCP does not
  expose `exec` or create.

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Node daemon and protocol: `infra/sandboxd/AGENTS.md`
- Data export requirements: `server/data-export.md`
