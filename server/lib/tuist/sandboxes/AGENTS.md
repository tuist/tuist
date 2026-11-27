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
admission keeps requiring the grant. Both daemons on a host take the host's
lock, and each grant loses what the other carve-out was asked to grow by since
the controller counted it (`allocation_sibling_memory_bytes`), so they cannot
both grow into the same free memory.
See [the rollout and recovery contract](../../../../infra/sandbox-image/remote-execution.md).

## Pieces

- `Tuist.Sandboxes`: context over `sandboxes`,
  `sandbox_agent_environments` and `sandbox_agent_sessions`; every state
  transition maps to one node command (`create`, `resume`, `pause`,
  `delete`, `exec`, `start_worker`). `handle_node_event/2` and
  `reconcile_node_report/2` absorb what the node reports back. The
  agent-session functions are delegated to `Tuist.Sandboxes.AgentSessions`.
- `Tuist.Sandboxes.AgentSessions`: starts Managed Agents sessions on an
  account's environment with the environment's credential
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
  ceiling (the template's `rootfs_bytes`, the largest of its tags on the
  node, which is also what sandboxd grows an older sandbox's rootfs to;
  `workspace_gb` and the memory
  image, all fixed-size files, plus 64 MiB): a new sandbox only goes to a
  node whose disk budget holds its ceiling on top of the ceilings of the
  rows placed there (creating, running, resuming) and of errored rows
  whose jail the node still reports, checked under the node's lock. A
  paused row the node reports paused with `disk_bytes` (its jail's
  exclusive bytes, measured after the pause) reserves that use instead,
  and the node keeps the largest growth one of its paused rows could make
  back to its ceiling, so one resume always fits; an unmeasured one
  reserves its ceiling. A resume takes the ceiling back under the lock and
  fails with `:no_capacity` (and moves off like a memory refusal) when the
  budget cannot take it; the disk-pressure sweep restores the reserve by
  archiving the oldest paused Orb. Production archives (2026-11-18) stored
  17 GiB at p50 and 21.5 GiB at p90 of rootfs, workspace and memory against a
  38 GiB ceiling for 4 vCPU / 8 GiB, template blocks a jail shares by reflink
  included, so the exclusive use a node reserves is lower still.
  Rows decide the state rather than the report, which lags: a delete frees
  its reservation at once. A resume also needs room for its next pause on
  the filesystem. `admission/2` is the check the poller runs on a work
  item: it dispatches an admissible item at once and otherwise
  acknowledges it and enqueues
  `Tuist.Sandboxes.Workers.DispatchWorkItemWorker` (secret Vault-encrypted
  in the args), which rechecks every 5 s and dispatches once it passes,
  force-stopping the item after 9 minutes (Anthropic stops an acknowledged
  item without a worker after roughly 10 to 13 minutes). The rejection
  reason (quota, or per node, with each macOS host's first failing check)
  is logged when the item is held, once a minute while it waits and at
  the deadline. When no node has disk for a new sandbox, `place/2` and the
  admission check ask `Archives.make_node_room/1` for room on those nodes
  (a snapshot copy, then an archived snapshot's node copy, then the archive
  of the oldest paused Orb or Claude Code sandbox, any account's), and the
  refusal stays
  `:no_capacity`, which callers retry. Never leave an item
  unacknowledged to wait for room: Anthropic offers it three times, 5 s
  apart, then stops; it stays `queued`, can no longer be acknowledged, and
  a new message does not requeue it (a stopped one is requeued by the
  session's next message). A node that reports no capacity or no disk
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
  only the last deferral stays asked for. A resume, which runs only on its own node and whose refusal archives the
  sandbox, instead waits out its node's deferral (up to 60 s) for as long as
  the grant still offers the memory, since the runners controller retires
  idle runners on a deferral; a revoked or shrunk grant ends the wait. `admissible?/2` asks for a growth
  and admits the item once the kubelet has applied it, within 2.5 s, which
  keeps the poller inside the queue's 5 s acknowledgement; otherwise the item
  stays queued. The chart's floor is 1 GiB, so every node's first sandbox
  grows its carve-out. `Tuist.Sandboxes.Workers.ShrinkCarveOutsWorker` (every
  minute) shrinks carve-outs back toward what their running sandboxes hold,
  never below the floor. It keeps a growth, and the room (memory and CPU
  guarantee) of an agent sandbox paused on the node, for five minutes, since
  each deferred growth retires an idle warm runner and each shrink lets a new
  one take the room; CI pressure or reclaim shrinks at once. It sends the daemon `reclaim` before the resize because the kubelet refuses
  to lower a limit below current usage; it also retries a shrink the kubelet
  has not applied and cancels a deferred growth no longer needed.
- Daemon CPU requests (`Capacity.sync_cpu/1`): a daemon that reports a CPU
  floor (`elastic.cpu_floor_milli`), under a ceiling above it, has its Pod's
  CPU request moved, without a limit, to the floor plus
  `Sandbox.guaranteed_cpu_milli/1` (a quarter vCPU per GiB of memory, or the creator's pick if more) of each
  creating, resuming or running agent sandbox on it, up to the ceiling
  (`Environment.sandbox_cpu_ceiling_milli/0`, the chart's `sandboxes.maxCpu`,
  else the one the daemon reports: the server reads it so that changing it
  restarts no daemon, since a restart pauses every sandbox on its node),
  through `Tuist.Kubernetes.Client.resize_sandbox_daemon_cpu/4` under the
  node lock. A growth goes, from the CPU the kubelet allocated, into the fresh
  grant's `cpu_free_milli` plus `cpu_reclaimable_milli` (idle warm runners'
  CPU, which the runners-controller retires when the kubelet defers the
  growth); a request the grant stops funding is lowered, since a deferred
  resize holds up memory growths. A shrink always goes, after the five-minute hold above for a paused sandbox's guarantee. Run on every
  `reconcile_allocation/1` and by `ShrinkCarveOutsWorker`; the last request
  the kubelet applied is cached per node and Pod for five minutes so an
  unchanged guarantee reads nothing. Placement holds
  it: `Capacity.cpu_room?/2`. See `infra/sandboxd/fleet-sharing.md` ("Disk and CPU").
- Placement packs Linux agent sandboxes (`Capacity.place/3`): after nodes in
  `prefer:`, the node with room that already runs the most sandbox memory
  wins, ties going to the most CPU the grant reports free. Sandboxes burst
  into each other's idle cores, and nodes left whole take runners. Remote
  execution VMs still go to the node with the most free memory.
- macOS placement (`MacosCapacity.place/3`) spreads instead: after warm VMs,
  the host with the most granted slots free wins, ties at random. Don't
  rely on `Nodes.connected_nodes/0`'s order: it is by name, so it fills one
  site's hosts (ber1) before another's (larch).
- Bursting and metering: a Linux agent sandbox boots with
  `Sandbox.burst_vcpus/0` (16) vCPUs whatever shape it asks for; the shape
  picks its memory. Each node report bills a running one the larger of its
  guarantee over the time since the previous report (at most 60 s) and the
  CPU its VM used (`cpu_ms`), as a `Tuist.Sandboxes.UsageEvent` row; the
  sandbox's `metered_cpu_ms`/`metered_at` hold the last reading and are
  cleared with `guest_cpu_ms` on pause. A pause bills the time since the
  last report from the `cpu_ms` the node returns with it, and a pause the
  server adopts from a report bills it from the `cpu_ms` the paused sandbox
  reports (once: the row is no longer running afterwards). A pause from an
  older daemon, a VM the daemon lost, or one `settle_running` adopts from a
  failed exec leaves it unbilled. `cpu_ms` counts the vCPU threads only. Memory is billed max(request, use): each running session's request
  from its lifecycle events, plus `excess_memory_mib_ms` on each usage row,
  what the VM's process held (`memory_anon_bytes` + `memory_file_bytes`,
  its Pss) past `Capacity.charge_bytes/1` over the interval; a pause bills
  its last interval from the readings in the pause result. Never meter
  `memory_current_bytes`: on staging most of it was the clean page cache of
  the template's or the VM's own memory file. `Analytics.compute/2` sums those rows
  for bursting sessions and counts other sessions' vCPUs (macOS, and Linux
  runs from before metering, up to their first metered report).
  `Concurrency` counts guarantees. The API's analytics report guaranteed
  vCPUs rounded up, since released CLIs decode them as integers.
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
  `list_events`, `send_message`, `archive_session`, `get_environment`).
  `list_events` fetches one page (`limit`, `order`, `page`,
  `created_at_gte` / `created_at_gt`) and returns `%{data, next_page}`.
  Non-2xx answers become `{:error, %{status, message}}`. Every call takes a
  credential, `{:api_key, key}` (sent as `x-api-key`) or
  `{:bearer, token}` (sent as `Authorization: Bearer`). `AgentSessions`
  resolves it from the environment row, read scoped to the caller's
  account: the federated token when all four federation ids
  (`anthropic_organization_id`, `anthropic_workspace_id`,
  `anthropic_service_account_id`, `anthropic_federation_rule_id`) are set,
  else `anthropic_api_key`, else `:missing_credentials`. The changeset
  accepts the four ids all or none.
- `Tuist.Sandboxes.Anthropic.Federation`: Tuist as an OIDC issuer for
  Anthropic Workload Identity Federation. One issuer per account,
  `<app url>/oidc/accounts/<account id>` (discovery and `jwks.json` served
  by `TuistWeb.OIDCIssuerController`), so a customer rule that trusts their
  issuer never accepts another account's tokens even without a `sub`
  check. `iss` and `sub` (`account:<id>:agent-environment:<id>`) always
  come from the environment row, never from the request. Each exchange
  signs a new ES256 JWT (5 minutes, fresh `jti`: Anthropic rejects reuse)
  and posts it to `/v1/oauth/token`; the access token is cached per node in
  `KeyValueStore` (never Redis) under the environment and its ids, and
  re-exchanged 2 minutes before expiry. The signing key is derived from the
  token-signing secret with its own purpose label
  (`AgentAuthSigningKey.derived_jwk/1`); rotation is in the moduledoc. The
  work queue (`Anthropic.Client`) still uses the environment key: whether
  federated tokens work on the environments work endpoints is untested.
- Connecting from the dashboard (`TuistWeb.Components.ClaudeIntegration`,
  Settings → Integrations) is one form: the customer creates the
  self-hosted environment and its key in the Console (only the Console
  generates environment keys) and pastes them with an API key (the
  default) or the four federation ids. The `connect_claude_environment` MCP
  tool takes the same inputs, and both go through
  `Sandboxes.connect_managed_agents_environment/3`, which fetches the
  environment with that credential (`fetch_anthropic_environment/3`) before
  the row is written,
  so a federated check signs with the setup subject `account:<id>:setup`
  (admitted by the recommended `account:<id>:*` prefix). The secrets go
  from the submitted form straight into the row and never into socket
  assigns.
- `Tuist.Sandboxes.Anthropic.Supervisor`: task supervisor + dynamic
  supervisor of the `Poller`s this replica started (one per enabled
  agent environment across the cluster, registered as
  `{:global, {Poller, agent_environment_id}}`), kept in sync with the
  table by `Manager` every 30s. Started on web pods outside tests
  (`sandboxes_children/0` in `Tuist.Application`).
- `Router.session_environment/2` decides the OS and Xcode a session runs
  on, for the poller's admission (`Router.admission/2`) and the router
  alike: an existing sandbox keeps its platform and template; a new one
  takes the `AgentSession` row's `platform` and `xcode_version`, else the
  `tuist_platform` (`linux`, `darwin`, `macos`) and `tuist_xcode_version`
  session metadata keys, else the environment's. An Xcode without a
  platform means macOS, and the environment's Xcode applies only on its own
  platform. Work items carry only the session id, so the keys are read with
  `ControlPlane.get_session/2` and the environment's credential. A failed
  read falls back to the environment's platform, except on a macOS
  environment, where it would boot the environment's Xcode in place of one
  the session may have asked for: the item is held
  (`:session_metadata_unavailable`) like an item without capacity. An
  unserved Xcode is admitted so `dispatch/2` logs the served list and stops
  the item without a sandbox. A platform other than the environment's runs
  that platform's default template and shape
  (`Sandboxes.platform_defaults/1`).
- `Tuist.Sandboxes.Xcode`: the Xcodes macOS sandboxes serve
  (`TUIST_MACOS_SANDBOX_XCODE_VERSIONS`, the default first) and the template
  each boots (`macos-xcode-<xcode-dashes>`; `macos` is the default). Create,
  agent environments, agent sessions and `create_sandbox` take an exact
  `xcode_version`, validated like a runner profile's; the template is what a
  sandbox keeps, so `Sandbox.xcode_version` is virtual. Amp orb types
  `macos-xcode-*` map to the same templates. See
  `infra/tart-kubelet/macos-sandboxes.md#xcode-templates`.
- `Tuist.Sandboxes.Router`: finds or creates the session's sandbox,
  resumes it and records the residency in one step
  (`Sandboxes.prepare_residency/2`), then starts `sbx-worker` with the
  session credentials; force-stops the work item on any failure so
  Anthropic re-queues it. A turn on a running macOS sandbox records
  its residency without a fresh CI grant (`MacosCapacity.admit_turn/2`):
  the VM already holds its slot, and CI and sandboxes are served first
  come, first served. Only a resume asks for the grant. Inside the residency
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
  the runner's credential: keep it out of rows and logs. The worker also gets
  `Sandboxes.tuist_env/2` (as Amp Orbs do); with it, `sbx-worker` runs
  itself as the runner's `--exec-path` session wrapper and hands each
  session's `CLAUDE_CODE_SESSION_ACCESS_TOKEN` to Tuist clients as
  `TUIST_OIDC_TOKEN`, which `Tuist.OIDC` accepts (`sk-ant-cc-` prefix,
  ES256 against Anthropic's JWKS, `ccr:role` `session_worker`, `aud`
  containing `ccr:pool_id`) for an enabled `claude_code` environment of an
  account with sandboxes, as a CI token with `account:sandboxes:write` (so a
  Linux session can drive a Tuist Mac with the image's Tuist CLI) that never
  outlives the session token. For the spawn hook's `repository_url`, each worker start allocates
  the repository's CI checkout volume
  (`Runners.CacheVolumes.allocate_sandbox_checkout/3`, one use per work id)
  and sends it as `start_worker`'s `checkout` with the guest path
  `<base-dir>/<owner>/<repo>`. The commit is the default branch's head from
  GitHub at allocation, never the guest's, so a session's export moves the
  master only to it; anything else only adds objects. The node seeds the
  guest from its master and takes the export behind the VM's fence
  (`infra/tart-kubelet/internal/macosandbox/checkout.go`, sandboxd's
  "Guest to host: checkout"). A new Linux sandbox of such a session goes
  first to the nodes where the account's sandboxes used that checkout in the
  last 6 hours (`CacheVolumes.recent_sandbox_checkout_nodes/4`
  into `Capacity.place/3`'s `prefer:`): they hold its master and, for
  sandboxd's `CHECKOUT_WORKSPACES_TTL`, the workspace prepared from that seed.
  The spawn admission's growth, the plain reservation and a carve-out growth
  prefer them, and placement grows one (waiting at most the admission's
  2.5 s) before taking another node's room; pausing idle sandboxes for room
  does not, since a pause costs about what they save. Placement logs
  `sandboxes: placed a sandbox with checkout nodes` with the nodes and the
  path it took (`room`, `grown`, `reclaimed`, `none`).
- `Tuist.Sandboxes.Workers.PauseSandboxWorker`: Oban job scheduled by
  `end_residency/1`; `Sandboxes.pause_idle/2` pauses only when the
  sandbox is still running, has no residency and the epoch it was
  enqueued with is still current, checked under the sandbox's lock.
- `Tuist.Sandboxes.DiskSnapshots`: disk snapshots (`sandbox_disk_snapshots`)
  of paused Amp Orbs, saved on the Orb's node by `save_disks` after a pause
  with `sync_disks` and keyed by account and Amp's `snapshot_id`. A new Orb
  spawned with that id goes to the snapshot's node (`Capacity.place_on_node/2`)
  and is created with `from_disk_snapshot`. While the archive tier is on, a
  ready snapshot is also uploaded (`archive_disks`, `ArchiveDiskSnapshotWorker`
  on the `sandbox_archives` queue, retried by `Archives.run/0` after a
  five-minute failure backoff, under `sandbox-archives/<account>/disk-snapshots/`) and keeps its
  node copy; when the node cannot take the Orb, lost the copy or the clone
  fails, an archived snapshot is created `from_archive` on any node with room
  (boot source `disk_snapshot_archive`), else the template boots. A copy the
  node loses keeps an archived row with `node_name` nil; a delete removes the
  object too. Each snapshot with a node reserves its
  rootfs and workspace ceiling in `Capacity.reserved_disk_bytes/1`, and the
  save itself is admitted under the node's lock
  (`Capacity.reserve_disk_snapshot/3`). A newer save replaces older copies
  of the same id, and of the id the saving Orb was spawned from
  (`sandboxes.amp_base_snapshot_id`), since Amp refreshes a project snapshot
  under a new id. Node reports reconcile them like sandboxes: copies no row
  places on the node are deleted from it, rows whose copy the node no longer
  lists lose it after a two-minute grace (dropped unless archived). A daemon that reports no
  `disk_snapshots` key is left alone.
  A macOS Orb's snapshot (`platform: :darwin`) is saved by its host as a
  stopped Tart VM after an eviction, which `save` records by clearing the
  row's `resident`; it reserves no server-side ceiling (the host reports its
  `bytes` in `disk.snapshots_bytes`, which `MacosCapacity.disk_room?` counts),
  records the host-measured `disk_bytes`, and a create from it goes only to
  hosts holding it (`MacosCapacity.place/2`); else an archived one is
  restored like an archived macOS session (`place_macos_restore/3`, `from_archive`
  with the snapshot's `template_tag`), and without an archive, or when that
  fails, the template boots on any host at once. Misses queue copies. It is
  archived and copied like a Linux snapshot, sized by `disk_bytes`, onto
  hosts serving its template that restore archives
  (`MacosCapacity.snapshot_hosts/1`, which clone the image it was saved
  from, pulled if their template moved on), admitted by
  `MacosCapacity.reserve_snapshot_copy/3`. Snapshot commands, which have no
  sandbox row, carry the host's current `node_uid` (`Nodes.command_args/2`).
  `Tuist.Sandboxes.Workers.DiskSnapshotRetentionWorker` (hourly) deletes
  snapshots unused for 72 hours and saves stuck for 15 minutes.
  An archived snapshot of a popular lineage (two Orbs spawned in its
  `lineage_id`, recorded on each Orb as `sandboxes.amp_snapshot_lineage_id`,
  in 24 hours) also gets extra node copies
  (`sandbox_disk_snapshot_copies`, `DiskSnapshots.copy/1`,
  `CopyDiskSnapshotWorker` on its own `sandbox_snapshot_copies` queue): the
  node downloads the archive (`copy_disks`) into its snapshot directory, under
  the snapshot's id. They are queued after a spawn that missed every node
  holding the snapshot and once a snapshot finishes archiving, so a refreshed
  snapshot of a busy project is copied out before its first miss. Count the
  lineage, not the Amp ids: Amp refreshes the snapshot at nearly every spawn
  and deletes the old row, so a fresh snapshot's own ids have at most one
  spawn when it is archived, and its copies came only after the next spawn
  had missed. Spawns
  place on any node holding a ready copy (`Capacity.place_on_node/2` takes the
  list). Copies are placed as runner cache volumes are
  (`Tuist.Runners.VolumePlacement`): by the snapshot's `lineage_id`, which a
  save inherits from the snapshot it refreshes (else the id its Orb was
  spawned from, else its own), so every snapshot of a project goes to the
  same nodes; on half again as many nodes as the lineage's Orbs held memory
  at once in the 24 hours (at least two, the snapshot's own node counting
  when it is one of them, and at most four copies), picked by weighted rendezvous hashing over the
  ready nodes at the archive's site, weighted by disk budget. Keep the key
  stable across refreshes: hashing the Amp id itself would move a project's
  copies at every refresh. A copy reserves the snapshot's ceiling on its
  node, is admitted only while that node's reserved disk stays under the
  archive high-water mark with it (so it never makes an Orb get archived;
  a node that cannot take it passes it to the next in rendezvous order), and
  is the first thing `Archives.make_node_room/2` gives up (the proactive
  `disk_pressure` sweep only gives up a copy unused for an hour: an Orb spawned
  on a copy pushes its node over the high-water mark, and dropping that copy
  re-downloaded a popular snapshot every hour). Once a node holds no copy to
  give up, an archived snapshot's own node copy goes next, least recently
  used first and under the same one-hour rule for the sweep
  (`drop_archived_node_copy/2`): the row keeps its archive with `node_name`
  nil, so the next spawn from it boots from the archive. Archived snapshots
  otherwise stay on their node until they expire, each holding a snapshot
  ceiling: in production (2026-11) 24 of them held about 720 GiB of the
  Linux fleet's 2.2 TiB budget while no node had room for a new sandbox.
  Copies go with their snapshot
  (expiry, supersede), after 24 hours unused, after 45 minutes stuck
  copying, and when their node stops listing them. A Claude Code repository
  snapshot is popular through its environment's sessions (builders, which
  have no session, do not count; sandboxes do not record their repository,
  so an environment's sessions count for each repository's snapshot), is
  placed by its environment and repository, and its copies may fill the
  node's whole disk budget instead of stopping at the high-water mark:
  Linux nodes run at the mark, which would refuse them all. A copy in use
  above the mark makes the disk-pressure sweep archive an idle Orb sooner.
  A Claude Code repository snapshot has no Amp id: it is keyed by
  `agent_environment_id`, `repository`, `setup_sha256` and `template`
  (a Linux environment's Macs keep one per Xcode template, which never
  supersede its sessions' snapshots), saved from a
  paused builder sandbox (`save_build/2`), and replaces the environment's
  older ready snapshots of the repository. `find_ready_for_repository/3`
  only returns one whose `template_tag` a connected node creates new
  sandboxes with, so a template rollout (which ships `sbx-worker`) is not
  held back by snapshots. A build is a row of the key in state `building`
  (no node, so it reserves no disk), `failed` once it failed; a partial
  unique index keeps one of either per key, so concurrent sessions start
  one build and a failed script waits an hour. `delete_expired/0` drops
  builds older than 90 minutes with their builder and failed rows after an
  hour.
- `Tuist.Sandboxes.ClaudeCodeSnapshots`: a `claude_code` environment's
  optional `setup_script`, on Linux and macOS. A macOS builder runs the
  script without `runuser` (guest commands already run as `runner`) and is
  placed only on a host where it leaves a granted slot free
  (`MacosCapacity`'s `slots/1`): it holds a slot for up to an hour and
  serves no session, so it waits for an idle host instead of taking one CI
  could use. A new Mac's idle pause can beat the builder's first command,
  and CI can take the slot it freed: that resume's `{:host_busy, _}`
  deletes the builder and a later step places a new one, rather than
  failing the build for an hour. A Linux environment's `macos_setup_script`
  prepares the Macs its sessions create through `Query.run(:create)` (the
  `create_sandbox` tool's `repository`, a github.com `owner/name` one of the
  account's projects is connected to; `mac_source/3`): the Mac boots from the
  repository's darwin snapshot of its Xcode template and workspace size, else
  bare with a build requested (`request_mac_build/1`, the default macOS shape).
  A Mac that boots from a snapshot older than six hours requests a build too:
  `tuist generate` takes more targets from the binary cache as it fills in
  after a push, which changes their dependents' build settings, and a
  session's first build recompiled 302 files of the Tuist app a few hours
  after its snapshot (measured, 2026-11). A build records the default
  branch's head it cloned (`commit_sha`, from GitHub through the account's
  installation), and `RefreshMacSnapshotsWorker` (every ten minutes,
  `refresh_mac_snapshots/0`) rebuilds a snapshot of the current script that
  is at least half an hour old once the head moved, while Macs were created
  for its repository on its template in the last day, so sessions boot from
  a recent head instead of waiting out the six hours. A builder whose create
  or command failed for the infrastructure (no room, a host that
  disconnected or timed out, CI taking the slot) is replaced on the next
  step; only a script that exits non-zero, or a builder that dies after its
  command started, fails the build and holds the key for an hour.
  Such a Mac records the repository (`sandboxes.repository`): the Macs
  created for it on the snapshot's template in 24 hours, except creates that
  failed (`error`), are the snapshot's spawns, which make it popular and so copied out like an Orb snapshot (the
  environment's Linux sessions count only for its Linux snapshots).
  Such a build clones to `$HOME/work/<name>`, `tuist sandbox sync`'s default
  (the name in the worktree's `origin` URL, so a local directory of another
  name lands there too):
  Xcode keys DerivedData by the workspace's path, so another path rebuilds
  from scratch. After the script it resets tracked files and records the
  clone as sync does (`$HOME/.tuist-sync/<cksum of path>/{id,paths}`, plus
  `commit`). The CLI's probe returns that commit, rebuilds its manifest from
  local Git objects and uses it only when its hash equals the recorded id, so
  the first sync is a delta and leaves unchanged files' modification times,
  which Xcode compares, alone (a full sync rewrites every file and rebuilt
  459 Swift files of the Tuist app in a measurement). A delta drops
  `commit`. Every boot mounts the Metal toolchain cryptex under a new random
  path. On Xcode 27.0 it reached the link line of host macro plugins built
  from source, so they relinked and their dependents rebuilt after any cold
  boot; with the macros taken from the binary cache (Xcode 27.2, 2026-11) it
  reaches only `ExtractAppIntentsMetadata` of targets that rebuild anyway. A Mac build's command starts as `:snapshot_build`, so its
  script gets a `TUIST_OIDC_TOKEN` with the CI preset on the account's cache
  that exchanges only while the build runs (`CommandCredentials`): an
  unauthenticated `tuist generate` skips the cache setup and writes other
  build settings than a session's, and the session's first build then
  recompiled everything (measured, 2026-11). Write access, not read, because
  the compilation cache's associations name objects a restored Mac can only
  fetch from the remote: a read-only builder left its publications in the
  spool, and a snapshot that also lacked one locally failed every session
  build with `CAS error: missing object` (2026-11). After the script the
  build drains the publications (`tuist-cas-proxy --drain`, as CI's
  `drain_cas_publications`) and fails when a record remains. The script runs without the
  clone's `GIT_TERMINAL_PROMPT`, since Tuist keys its package-manifest cache
  on the environment and a session's commands lack it. After the script the build
  deletes the CLI's stored session (`~/.config/tuist/credentials`) and the
  simulator devices the script created, shuts the image's down and stops the
  simulator services, since runtimes mount at new paths on each boot and a
  Mac restored with the builder's devices and simulator state lost its iOS
  runtime; one restored with the image's devices kept them and its runtimes
  (measured, 2026-11). `Query.run(:create)` starts booting the image's newest
  Pro iPhone on a prepared Mac as a sandbox command
  (`Devices.boot_in_background/1`), so it is ready by the time the session's
  first build ends instead of booting cold after it. Before that it stops
  every `tuist.*` launch agent and the build service and waits for each to
  exit (`launchctl bootout` returns first, as CI's `stop_tuist_launch_agents`
  notes), ends whatever `lsof` still finds in `CompilationCache.noindex`,
  and flushes every file in DerivedData with `F_FULLFSYNC`. The build ends
  with `sync`, and the save shuts the builder's guest down cleanly
  (`save_disks` with `shutdown`) instead of checkpointing it, so the
  snapshot holds unmounted file systems; nothing resumes a builder.
  Disks a running guest had only synced and flushed were not enough:
  restored Macs read `data.v1` with a zeroed header or missing objects
  ("not a IncludeFileList node kind", "specified header offset (16) does
  not match existing config (0)"), or an index whose trie crashed
  `tuist-cas-proxy` in `OnDiskTrieRawHashMap::insertLazy` on the session's
  first cache writes, so every later build failed with "The Xcode build
  system has crashed" (measured, 2026-11). A host that predates `shutdown`
  ignores it and evicts the builder as before. The snapshot's key hashes the build script with the macOS setup script, so changing either rebuilds it.
  `ClaudeCodeRunners` creates a session's sandbox
  from the repository's snapshot; a new session without one starts on the
  template and, after its worker started, requests a build. Nothing runs
  in a session's sandbox before its runner, so the spawn lease never limits
  the script. `BuildRepositorySnapshotWorker` snoozes through the build:
  a builder sandbox with the build's id (`create_sandbox/3`'s `id:`) runs
  one `Commands` command with the build's id too (an hour at most) that
  clones as `user` with a contents-read token in its environment, unsets
  it and runs the script as `user` in a login shell with
  `Sandboxes.tuist_env/2`. Exit 0 pauses the builder (syncing its disks),
  saves and deletes it. The snapshot takes over the builder's disk
  reservation (`Capacity.reserve_disk_snapshot/4`'s `releases:`): nodes run
  near their budget, and a second ceiling on top of the builder's would be
  refused. A save the node still refuses (its filesystem) keeps the paused
  builder, asks `Archives.make_node_room/1` for room and retries every
  minute until the build expires. Anything else logs the output's tail, deletes the
  builder and fails the build. Never save a sandbox a session used: every
  later session of the environment boots from the snapshot.
- `Tuist.Sandboxes.Archives`: the archive tier of paused Amp Orbs,
  Claude Code sessions' sandboxes, legacy Tuist threads' sandboxes (provider
  environment `threads/<id>`, retained for offline conversation export)
  and, on macOS, every evicted paused
  sandbox, whose disk the Mac shares with CI (other Linux sandboxes are
  archived only off a node CI takes or that refused their resume; their next
  spawn restores them too, since `Router.find_or_create_sandbox/3` keeps an
  archived row and `prepare_residency/3` restores it). Before Claude Code
  sandboxes were archived, paused ones held their ceilings for the 14-day
  retention (in production, 2026-11, 16 of them held about 544 GiB). An Orb
  paused longer than `Environment.sandbox_archive_after_hours/0` (off when
  unset), or the least recently paused one on nodes whose disk refused a new sandbox (`make_node_room/1`, at most
  one upload from them at a time), is uploaded by its node (`archive` command with presigned multipart
  part URLs; the daemon holds no storage credentials) as kernel, rootfs and
  workspace, with the memory image and VM state ahead of them when the
  server asks (`memory: true`) and the image is current, to `sandbox-archives/<account_id>/`
  in the archive bucket of the in-rack store at the node's site (a shard
  storage target with an `archive_bucket`, recorded in `archive_store`), or
  in the account's storage when there is none available, the store's shared
  `archive_budget_bytes` is reached (100 GiB by default, production 500 GiB,
  canary 100 GiB), or the account has its own
  S3 storage. The sandboxd NetworkPolicy lets the daemon reach the store
  and the daemon drops guest traffic to its port. The row
  becomes `archived` with `node_name` nil only after the upload is
  completed and readable, then the jail is deleted; an `archived` row a node
  still reports is deleted from it. The upload runs without the sandbox
  lock (taken only to start and to finish), so a resume wins: the node
  cancels the upload and `finish` discards one whose row changed. A spawn
  of an archived Orb (`running_or_resume/1`) is admitted like a create
  (the CPU and memory quota), placed by
  `Capacity.place/1`, or by `place/2` among the nodes at its store's site,
  created
  with `from_archive` and cold boots; a failed restore reverts the row to
  `archived`, never to `error`, because the object is the only copy. An
  archive with memory (`archive_memory`: the disk stream's `tail_offset`
  and `tail_sha256`, and the writing node's `compat`, its hello's
  `snapshot_compat`: CPU model, microcode and flags, full host kernel
  release and Firecracker version) is placed only on nodes with the same
  `snapshot_compat`, waiting for room on them, and on the node it was
  archived from (`archive_memory.node`), or on a node still loading another
  warm restore's memory (`Archives.restoring_nodes/0`: restores on one node
  share its bandwidth to the store, and three at once hit the guest agent's
  60 s timeout in production), only when no other of them can take
  it (`Capacity.place/3`'s `avoid:`), and resumes warm: the node
  downloads only the disk stream, loads the VM state with a Uffd memory
  backend and serves memory chunks by ranged GETs as the guest touches
  them while a fill fetches the rest (sandboxd `internal/uffd`). It cold
  boots elsewhere only when no such node is connected. A node whose hello
  sets `lazy_disks` is asked to archive with `lazy_disks` too: the disks
  are chunked like the memory and served by range on restore, so the guest
  runs before they arrive; such an archive (`archive_memory.lazy_disks`)
  is placed, warm or cold, only on nodes that set `lazy_disks`. The
  object is deleted once the restored sandbox runs (`delete_restored/1`),
  after a warm restore only once its node reports `memory_loaded` (or two
  hours later), with the sandbox, or with the account. A warm restore's row
  becomes `running` and `loading_since` in one transaction: `run/0` deletes
  the archive of any running row without it, and in production
  (2026-11-25) one between two separate updates deleted a lazy-disk
  restore's only copy. `archived` rows are outside every
  node reservation and the CPU and memory quota. Each store's archive budget counts Orb
  and disk snapshot archives across all accounts, including restored objects
  awaiting deletion, leaving room for shard artifacts; uploads can cross it.
  There is no per-account archive limit. Account-storage archives have no cap.
  Budget or measured physical-space pressure offloads completed Orb and snapshot archives oldest `archived_at` first to account storage. Verify the destination size and SHA-256 before switching the recorded key/store; retain the old copy for two hours for signed restores, with durable cleanup jobs. Preserve direct-to-account fallback until rack capacity is actually available. No Orb archive expiry is added. There is no count of paused Orbs per account.
  `Tuist.Sandboxes.Workers.ArchiveSandboxesWorker` (every minute) runs
  `Archives.run/0`, which also queues the oldest idle Orb on each node above
  `Environment.sandbox_archive_disk_high_water_percent/0` (default 85% of
  the reserved disk budget, snapshot copies included), rechecking pressure
  before uploading. Real failures back off for five minutes from the attempt; a newer `paused_at` bypasses an older attempt without bypassing pause age or upload/residency guards. Node transport interruptions and abandoned uploads clear backoff. Each Orb upload atomically queues `RecoverArchiveUploadWorker` for five minutes later. A separate cluster-wide upload lock spans the caller's transfer, without a pooled connection or blocking resume/delete; recovery retries in a minute while that caller is alive, otherwise discards only that upload and requeues a still-paused Orb. Process/replica death releases the lock regardless of Oban state. Releasing the upload claim and requeueing commit together. Keep the 45-minute abandoned-upload sweep as fallback for pre-rollout Orb uploads and snapshot uploads. Restores stuck for 15 minutes are reverted.
  Moving off a node CI takes: a paused Linux sandbox resumes only on its own
  node, so while the runners-controller's allocation for a node asks for a
  reclaim (`Capacity.ci_reclaim?/1`, a host reservation or unhealthy node,
  not an expired grant), `ReclaimCapacityWorker` calls
  `Archives.move_off_node/1` after pausing the idle ones: two minutes later,
  if CI still reclaims the node (most Linux host reservations end within
  that, and a moved session waits for a restore instead of a resume), it
  archives the
  least recently paused sandbox there of any source (not remote execution),
  whatever its pause age, one upload from the node at a time, each
  allocation observation queuing the next, and rechecks the reclaim before
  uploading. A resume the node refuses for room (`:no_capacity`, not quota)
  queues that sandbox's archive too (`Archives.move_off/1`). CI waits on none
  of it. A resume the node admits during an upload cancels it and resumes
  warm; one still refused keeps answering `:no_capacity` until the archive
  completes, after which it restores on any node and cold boots (files kept,
  processes and memory lost). Off with the tier. Archived non-Orb rows keep
  the 14-day retention of their pause.
  macOS sessions move the same way once evicted (`resident` false; a
  resident pause still holds its VM and is never archived), from hosts
  whose hello sets `archives`: a darwin report whose fresh grant is denied
  (`MacosCapacity.ci_reserved?/1`, CI's host reservation) calls
  `move_off_node/1`, and a refused resume (`:no_capacity` or
  `{:host_busy, _}`) calls `move_off/1`. The host uploads the stacked
  clone's disk delta (`overlay.asif`, `config.json`, `nvram.bin`) with no
  memory: its checkpoint is encrypted for that Mac, so a moved session
  always cold boots. A restore goes to a Mac with `archives` and the
  template (`MacosCapacity.restores?/2`), one already running the archived
  `template_tag` first (`runs_image?/2`), then Macs without a warm VM (a
  restore cannot claim one, and it holds one of the host's two slots); a Mac
  that refuses it passes it to the next, as a new create does. It passes that tag in the create,
  so a host on a newer release pulls the archived digest, and waits up to
  31 minutes (not reverted as stuck before 35). Hosts without `archives` back
  their sessions off like a failed upload. Disk pressure is Linux-only.
  Before a cordoned box's Machine is deleted, operators run
  `Tuist.Release.sandbox_node_drain/1` (`Archives.node_drain/1`): it lists
  the agent sandboxes still on the node, queues the next archive, and
  raises until only errored rows are left (the runbook is
  `infra/runners-controller/AGENTS.md`, "Replacing a runner box").
- Account limits (`Tuist.Sandboxes.Concurrency`), never a count: running
  sandboxes (creating, running or resuming) charge the CPU and memory quota
  (`:sandbox_concurrency_limit`, checked on create, restore and resume,
  retryable). The admission locks the account row with `SKIP LOCKED`, so any
  transaction holding that row answers `:sandbox_account_busy`; outside a
  transaction `Concurrency.admit/3` tries again for 3 s first. Legacy Tuist threads' sandboxes are hidden from the account and use
  none of it (`Sandboxes.not_thread/0`). Disk is not an account limit: each node's disk budget bounds
  it, and archiving frees it, so concurrency analytics chart no disk.
- Idle Orbs: node reports carry each running VM's `cpu_ms` (on macOS the server reads
  it only for Orbs). A reading more
  than 20 ms per second above `guest_cpu_ms` since `last_active_at`, or
  below it (a new VM process), records activity. A running Orb quiet for
  ten minutes enqueues `Tuist.Sandboxes.Workers.PauseIdleOrbWorker`, which
  calls `AmpOrbs.pause_idle/2`: under the Orb's dispatch lock, it pauses
  only if `last_active_at` is unchanged, the same way Amp's pause does.
  Without `cpu_ms` (an older daemon), `guest_cpu_ms` stays nil and nothing
  is paused.
  Amp does not repeat a pause the node refused while a warm restore's disks
  load (`:restoring`), and an Orb whose services keep its CPU busy never
  looks idle, so the refusal queues `PauseRestoredOrbWorker`, which pauses
  the Orb once the disks are whole unless a later spawn moved its
  `residency_epoch`. Without it, restored Orbs of archived threads held 8 of
  the Linux fleet's ~45 slots for up to three days (2026-11-26).
- Lifetimes: a sandbox `Query.run(:create)` creates (the account API, MCP
  `create_sandbox`, `tuist sandbox create`) has `lifetime_seconds` (two hours
  by default, five minutes to a day) and `expires_at`, set at create and
  started again by every resume or restore (`running_or_resume/1`) and by
  `extend/2` (`POST .../extend`, MCP `extend_sandbox`). Every minute
  `ExpireSandboxesWorker` (`expire_sandboxes/0`) ends an expired running one
  hard: `Commands.cancel_expired/2` kills its commands without resuming it,
  appends a note to each one's stderr (written before the kill marker, so a
  reader sees it with the end) and records them `cancelled`, then it pauses;
  agents extend first (the `create_sandbox` description says so). It queues
  the archive of an expired paused one once archivable (a Mac after its host's
  eviction, about 30 s later). `Commands.read/3` answers an ended command of
  an expired, paused sandbox from its row: resuming to read output would
  start a new lifetime. Archive, not delete: the files survive, a
  resume restores them, and the 14-day retention deletes the rest. Sandboxes
  of Amp Orbs and agent environments (Claude) have no lifetime and are never
  expired: their integrations own them.
  Guest CPU never records activity on a non-Orb Mac: there `last_active_at`
  is the session lease, and a guest busy on its own (indexing, a simulator)
  kept a forgotten Mac and its CI slot running for as long as nobody used it.
- `Tuist.Sandboxes.Workers.RetentionWorker`: daily cron (shared crons in
  `Tuist.Oban.RuntimeConfig`) that deletes sandboxes paused, or errored,
  for longer than 14 days (both may still hold their disk; a failed macOS
  create no longer does, see Invariants), falling back to
  the row's last update when the node paused the sandbox without the
  server recording `paused_at`.
- Idle pauses: a create, a resume or an exec that leaves a sandbox
  running without a residency (re)schedules `PauseSandboxWorker` after
  the grace period with the current epoch, so API-driven sandboxes are
  paused once idle like agent ones; a residency starting meanwhile bumps
  the epoch and the pending job does nothing. A node refuses to pause a
  warm restore whose lazy disks still load, which can outlast the job's
  retries, so its `memory_loaded` event schedules the idle pause again.
  A node also refuses while an exec runs, so the job snoozes 15 s on that
  refusal instead of spending its retries. The server waits for an exec
  20 s past its `timeout_ms`, longer than the node keeps it (sandboxd's
  10 s deadline slack plus up to 5 s to kill the guest process; 5 s on
  macOS): when the server gave up first, an Orb's timed-out
  bootstrap ended its turn while the exec was still in flight, and the
  immediate pause of a shared node was refused (2026-11).

Shared-fleet admission requires a fresh controller allocation on `sandbox_nodes`.
CI reservation revocation, zero extra warm memory, timestamp ordering and resize
serialization are specified in [`fleet-sharing.md`](../../../../infra/sandboxd/fleet-sharing.md).
`ReclaimCapacityWorker` applies pressure after the allocation is committed.
Shared-node idle pauses (all macOS hosts too) have zero grace and enqueue
shrink work, except 20 s after the last command ends on Linux (`Commands`
residency), so a command run such as a sync then a build does not wait out a
pause and a resume; CI pressure still pauses that idle sandbox at once. CI demand never pauses or evicts a running macOS VM: there the grant
gates only creates and resumes. On
macOS the `Commands` residency itself outlives the last command as the
session's ten-minute lease (see `Commands` below). Active residencies and
daemon worker/exec guards remain authoritative.

Account compute admission is independent of CI: `Tuist.Sandboxes.Concurrency`
charges creating, resuming and running rows against account vCPU/RAM limits.
Create and resume must reserve quota in the same transaction as their state
transition, under the account row lock. Never hold that lock across node or
Kubernetes calls. Ops can adjust the limits; public account changesets must not
cast them. Pauses release compute quota.

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
  node reporting a sandbox in `error` errors the row with its reason,
  except a warm restore still loading lazy disks
  (`Archives.loading_disks?/1`, until `memory_loaded`), which reverts to
  `archived`, even from `error`, as do the other paths that would error
  it. sandboxd errors such a jail when it restarts, and a placed `error`
  row is never restored, so it would strand its Orb. A revert records
  `failed` for a row that had started running and drops its
  `loading_since`. An error report from a node the row is not on is a
  stale copy: only that node's jail is deleted, never the row changed.
- A failed macOS create holds nothing. It never ran (`last_active_at` is
  nil), so `boot/5` deletes it from its host at once and the row keeps
  `error` and its `error_message` with no node, `node_uid` or `resident`:
  the form a create refused for room has, which Amp Orbs, Claude Code
  sessions, Managed Agents sessions (`Router.find_or_create_sandbox/3`,
  `MacosCapacity.admission/2`) replace with a fresh create, while a placed
  errored Mac still answers `:sandbox_recovery_required`. A host that
  cannot delete it then does when it next reports it in `error`. A report
  that no longer lists an errored macOS row clears its `resident` (only an
  error report did, and a host lists none for a VM it deleted, so the row
  held CPU, memory and a slot for the 14-day retention) and releases a
  failed create's node. In production (2026-11-21) such rows, resident
  ones and ones on the disk budget of hosts that still listed them,
  refused every macOS create on a whole rack. We kept
  the row rather than deleting it: it is the failure's record, the API,
  the dashboard and `Tuist.Runners.MacosSandboxWarmPools` (refused and
  failed creates are demand) read it, and the retention removes it like
  any errored row, counting from the failure. Every `failed` event keeps
  the error, node and template (`Events.record/3`), so the failure
  outlives the row when a retry, a delete or the retention removes it.
- A node that left the cluster never reports again. Every minute
  `ReleaseRemovedNodesWorker` (`Sandboxes.release_removed_nodes/0`) errors
  the Linux agent rows of a node that is not connected and whose Kubernetes
  Node answers 404, with `node_name` nil, so spawns and routers start them
  afresh; an interrupted restore reverts to `archived`. Any other answer
  leaves them alone. macOS rows are left to recovery: tart hosts are virtual
  Nodes that can deregister and return with their VMs.
- `environment_key` is `Tuist.Vault.Binary` encrypted and never
  serialized by the API. It travels only inside `start_worker` args.
- `anthropic_api_key` is `Tuist.Vault.Binary` encrypted, never
  serialized by the API (`has_api_key` is), and only ever used
  server-side by `ControlPlane`. Federated access tokens live only in the
  node's in-memory cache and are never persisted or serialized. Installation tokens used for private
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
  once but an agent turn refuses them with `:busy`. `release_if_idle/2`
  ends it under the sandbox row lock once no row is `running`; `start/2`
  inserts its row before holding, which closes the race with a release.
  On macOS it is kept instead as the session's lease: joining it needs no
  grant, the host hold gets `hold_ms` (lease plus two minutes) as a
  backstop, and `EndLeaseWorker` ends it once `last_active_at` is ten
  minutes old. `Query` create and resume take it too (`keep/1`). A refused
  start (`:no_capacity`, `{:host_busy, _}`) is retried inside the request
  every second for 25 s, so a command starts within a second of its host
  freeing.
  Every command gets `STRUO_PROGRESS` (unless its env sets one) naming
  `struo-progress.jsonl` in that directory, and `read/3` returns the file's last
  line as `progress`, so callers can show a Struo build's progress without an
  extra exec; the guest writes it, so validate it before use. Legacy clients get
  `ONCE_PROGRESS` pointing at the same default file; reads also accept the old
  `once-progress.jsonl` for commands started before the rename.
  A caller that already holds a residency passes it as `:residency`: the command joins it
  instead of `commands`, and `release_if_idle/2` leaves it to its holder.
  `pause_idle/2` skips a sandbox with running commands.
  A command the API starts (`:started_by`, the caller) in a member sandbox
  gets `Sandboxes.tuist_env/2` and, as `TUIST_OIDC_TOKEN`, an identity token
  from `CommandCredentials`, minted at each launch: signed with the token
  secret under its own salt (not a JWT any API accepts), bound to the
  command, its sandbox and account, expiring at the command's deadline, and
  exchanged by `Tuist.OIDC`/`OIDCController` only while that command's row is
  `running` in a member sandbox of a flagged account. Its grant is computed at
  mint and never exceeds the starter's own cache access (`ci` when they may
  write the account cache, the CI preset scopes an account token holds and its
  projects; cache read when they may only read; no token otherwise), and
  never includes `account:sandboxes:write`. The caller's `env` overrides
  these variables. Keep it out of rows, logs and responses; nothing is cached,
  so any replica verifies it. `CommandWatchWorker`
  kills each command at its deadline and records commands no client reads.
  The logs endpoint streams ND-JSON by looping `read/3` with 25 s waits,
  under proxy idle timeouts. Starting a command and writing stdin are
  idempotent only when the client sends a start `id` and stdin `offset`:
  a proxy 502 can hide an answer whose effect already happened, so clients
  replay these requests only with them. Never end the residency with
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
  `FeatureFlags.sandboxes_enabled?/1` (on canary and production, any of
  `:sandboxes`, `:linux_sandboxes` or `:macos_sandboxes`), and the poller
  manager only runs pollers for flagged accounts. Platforms open separately:
  `Sandboxes.create_sandbox/3` refuses a platform the account lacks
  (`FeatureFlags.sandbox_platform_enabled?/2`: `:sandboxes` covers both, the
  others one each) with `platform_not_enabled` (403) before admission, and
  Amp gets a final 403 for that Orb type. Turning a platform flag's boolean
  gate on opens that platform to every account. Accounts get the shapes in
  `Sandbox.shapes/0` and workspaces up to 100 GB.
- `TuistWeb.API.SandboxesController`: API under
  `/api/accounts/:account_handle/sandboxes` (agent environments,
  including `PATCH agent-environments/:id` for the API key, the federation
  ids, model and system prompt; agent environments are serialized with
  `federation_issuer_url` and `federation_subject`; sandboxes, exec,
  commands, pause/resume/delete). Members and account tokens with
  `account:sandboxes:write` (`:sandboxes_write`) reach every sandbox action
  (list, show, analytics, create, exec, commands, uploads, pause, resume,
  archive, delete) on every plain sandbox in the account
  (`Sandboxes.member_sandbox?/1`), and manage (show, pause, resume, extend,
  archive, delete) the ones that serve an agent environment, an Amp Orb, a
  provider environment or remote execution. Reaching inside those (exec,
  commands, uploads) stays admin-only (`require_guest_access/2`): their guest
  holds someone's checkout and the integration's credentials, such as a
  Claude Code session's work order, which `exec` (root in the guest) reads,
  and a Claude Code session or an Orb exchanges its own token for
  `account:sandboxes:write`, so a prompt-injected session would otherwise
  read everyone else's. An account token is never an administrator. Agent
  environments, which hold Anthropic credentials, and Orb dispatch stay
  admin-only. The MCP sandbox tools expose no guest access and apply the
  same rule. Exec and command starts log their caller (never the command),
  which no row stores.
- Dashboard: `TuistWeb.SandboxesLive` (`/:account_handle/sandboxes`),
  `SandboxInstancesLive` (`/sandboxes/instances`) and `SandboxLive`
  (`/sandboxes/:sandbox_id`) raise `NotFoundError` unless the flag is on and
  `:sandboxes_read` allows the user; the sidebar entry uses the same gate.
  Pause, resume, archive and delete require `:sandboxes_update` (members), are
  rechecked per event and run in `start_async`, since node commands block.
  Pause goes through `pause_idle/2`, so it never interrupts an agent turn,
  and Amp Orbs are not resumed or restored from the dashboard (Amp does it).
  Archive (`Sandboxes.archive/1`) only queues `ArchiveSandboxesWorker` for
  one paused sandbox of any source,
  because the upload outlives a page. The app layout renders no flashes, so
  these pages render theirs with `SandboxesLive.flash_alerts/1`.
  The overview charts come from `Analytics` over ClickHouse
  `sandbox_events`, which `Events` writes on every state change: through
  `update_sandbox/3`, and explicitly where a state is written another way
  (create, delete, `mark_error`, `Archives`). A new state write must record
  its event too, or sessions and concurrency drift. `boot/2` times each
  boot (create or restore) and tags its `started` event with what it booted
  from. Before every Amp pause, `AmpOrbs` reads the birth and modification
  times of Amp's `setup.log` in the guest (`Sandboxes.exec_running/3`, which
  neither resumes nor counts as activity) and records a `setup` event dated
  when setup finished; a log older than the row came with a disk snapshot
  and is ignored. The Setup and Time to start widgets chart those
  durations; vCPU-hours and memory GiB-hours (`Analytics.compute/2`) are
  on the Usage page, priced by `Sandboxes.Pricing` per vCPU-hour and per
  GiB-hour of reserved memory, disk included. There is no Stripe meter yet: early access covers the whole
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
  errors to one HTTP status, a stable `code` and a message (`Query.error/1`);
  the API sends `{message, code}` and MCP tools lead their error text with
  `code: <code>`. Codes are a contract: never change one's meaning, add new
  ones to `Query.error_codes/0`. The API sends every 503 with a
  `retry-after` (300 s) longer than the CLI's retry budget: the server has
  already waited for the node, so replays only repeat the wait. A create
  is limited per account (10 a minute, `rate_limited` with its own
  `retry-after`) and, when every host refuses it for room, places the same
  row again every 2 s for 25 s (`create_sandbox/3`'s `capacity_wait_ms:`)
  before it answers `fleet_busy`, which tells agents not to loop. The account's
  CPU and memory limit is a separate 429 (`account_limit`). A create refused
  for room records no `created` or `failed` event (its row stays `error`,
  which callers replace and the warm-pool signals count as demand). We
  considered accepting such a create as `queued` and placing it later: it
  needs a new state every node report, quota and retention path handles,
  while the wait reuses the commands path's own wait and fits a Mac boot
  inside MCP clients' 60 s tool timeout.
  Every caller
  requires an account administrator and the sandboxes flag, read-only
  calls included, because sandboxes run arbitrary commands. MCP does not
  expose `exec`. Its device tools (`Tuist.Sandboxes.Devices`) run fixed
  scripts through `exec` with user values only in environment variables; keep
  it that way. Script exit codes 3–6 map to `devices_unsupported`,
  `device_not_booted`, `device_not_found` and `app_not_found`. They are named
  for devices, not simulators, so Android emulators can join as another
  `platform`; a Linux sandbox answers `devices_unsupported` before any exec. The
  screenshot is a scaled JPEG because synchronous exec caps stdout at 1 MiB.

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Node daemon and protocol: `infra/sandboxd/AGENTS.md`
- Data export requirements: `server/data-export.md`
