# Sandboxes (Context)

Server control plane for the Firecracker sandboxes run by `sandboxd`
(`infra/sandboxd/AGENTS.md` is the protocol and lifecycle spec). One
sandbox is one persistent microVM per coding-agent session; the first
consumer is Claude Managed Agents `self_hosted` environments.

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
  filesystem. `admissible?/2` is the side-effect-free check the poller
  runs before acknowledging a work item. A node that reports no capacity
  or no disk budget is not budgeted on that resource.
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
- `Tuist.Sandboxes.Router`: finds or creates the session's sandbox,
  resumes it and records the residency in one step
  (`Sandboxes.prepare_residency/2`), then starts `sbx-worker` with the
  session credentials; force-stops the work item on any failure so
  Anthropic re-queues it. The residency that creates the sandbox also
  binds it to the `AgentSession` row (looked up by
  `anthropic_session_id`) and clones the requested repository into
  `/workspace/<name>` with `git clone --filter=blob:none` (branch via
  `--branch`, a commit sha via a follow-up `checkout`; 90s budget). A
  github.com repository named on the `AgentSession` row is cloned with a
  token minted for that one repository with `contents: read`
  (`GitHub.App.create_scoped_installation_token/4`), passed to git as
  an `http.extraheader` through `GIT_CONFIG_*` environment variables so
  it never lands in `.git/config`. A repository named only in the
  session metadata (which anyone with access to the Anthropic workspace
  can set) is cloned anonymously. A failed clone is logged and the
  worker still starts.
- `Tuist.Sandboxes.Workers.PauseSandboxWorker`: Oban job scheduled by
  `end_residency/1`; `Sandboxes.pause_idle/2` pauses only when the
  sandbox is still running, has no residency and the epoch it was
  enqueued with is still current, checked under the sandbox's lock.
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

## Multiple replicas

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
  flagged accounts. Accounts get at most 50 live sandboxes, the shapes
  in `Sandbox.shapes/0` and workspaces up to 100 GB.
- `TuistWeb.API.SandboxesController`: account-admin API under
  `/api/accounts/:account_handle/sandboxes` (agent environments,
  including `PATCH agent-environments/:id` for the API key, model and
  system prompt; sandboxes, exec/pause/resume/delete).
- `TuistWeb.API.AgentSessionsController`: account-admin API under
  `/api/accounts/:account_handle/sandboxes/agent-sessions` (create,
  list, show with live status and usage, `messages`,
  `events?after=<cursor>`, `archive`).

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Node daemon and protocol: `infra/sandboxd/AGENTS.md`
- Data export requirements: `server/data-export.md`
