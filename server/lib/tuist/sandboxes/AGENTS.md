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
  `archive_agent_session/1`). The agent is created on first use with the
  environment's `agent_model` and `agent_system_prompt` and cached in
  `anthropic_agent_id`; a per-session `model` override gets an uncached
  agent, and `agent_id` runs an existing one. The row id is generated
  before the Anthropic call and travels in the session `metadata`
  (`tuist_agent_session_id`, `repository_url`, `repository_ref`).
- `Tuist.Sandboxes.Nodes`: `Registry` of connected nodes (name to socket
  pid plus capacity/templates/sandboxes) and `call/4`, the blocking
  request/response bridge onto `TuistWeb.SandboxNodeWebSock`, with
  `on_stream` for `exec` output.
- `Tuist.Sandboxes.Anthropic.Client`: Req client for the work queue
  (`poll`, `ack`, `stop`, `stats`), authenticated with the environment
  key. `TUIST_ANTHROPIC_API_URL` overrides the base URL.
- `Tuist.Sandboxes.Anthropic.ControlPlane`: Req client for `/v1/agents`
  and `/v1/sessions` (`create_agent`, `create_session`, `get_session`,
  `list_events`, `send_message`, `archive_session`), authenticated with
  `x-api-key`. Non-2xx answers become `{:error, %{status, message}}`.
- `Tuist.Sandboxes.Anthropic.Supervisor`: registry + task supervisor +
  dynamic supervisor of one `Poller` per enabled agent environment, kept
  in sync with the table by `Manager` every 30s. Started on web pods
  outside tests (`sandboxes_children/0` in `Tuist.Application`).
- `Tuist.Sandboxes.Router`: finds or creates the session's sandbox,
  resumes it, records the residency and starts `sbx-worker` with the
  session credentials; force-stops the work item on any failure so
  Anthropic re-queues it. The residency that creates the sandbox also
  binds it to the `AgentSession` row (looked up by
  `anthropic_session_id`) and clones the requested repository into
  `/workspace/<name>` with `git clone --filter=blob:none` (branch via
  `--branch`, a commit sha via a follow-up `checkout`; 90s budget). A
  github.com URL is cloned with the account's GitHub App installation
  token when one exists. A failed clone is logged and the worker still
  starts.
- `Tuist.Sandboxes.Workers.PauseSandboxWorker`: Oban job scheduled by
  `end_residency/1`; pauses only when the sandbox is still running, has
  no residency and the epoch it was enqueued with is still current.

## Invariants

- The sandbox row exists before the node hears its id, so a node report
  that races a create never looks like an orphan. Ids a node reports
  that the database does not know are deleted from the node.
- `residency_epoch` increments on every residency start and end; it is
  what makes a scheduled pause safe to leave enqueued.
- `environment_key` is `Tuist.Vault.Binary` encrypted and never
  serialized by the API. It travels only inside `start_worker` args.
- `anthropic_api_key` is `Tuist.Vault.Binary` encrypted, never
  serialized by the API (`has_api_key` is), and only ever used
  server-side by `ControlPlane`. Installation tokens used for private
  clones live only in the `exec` argv; git output is redacted before it
  is logged.
- `anthropic_agent_id` is only cached for the environment's own
  `agent_model`; `AgentEnvironment.update_changeset/2` clears it when
  the model or the system prompt changes.
- `Nodes.call/4` must never run on the socket process itself (it waits
  on a message that process has to deliver); report handling spawns
  orphan deletes via `Tuist.Tasks.run_async/1`.

## Web layer

- `TuistWeb.SandboxNodesController` (`GET /api/internal/sandboxes/nodes/connect`):
  TokenReview with the `tuist-sandboxes` audience, namespace check,
  `X-Tuist-Node-Name`, WebSocket upgrade to `TuistWeb.SandboxNodeWebSock`.
- `TuistWeb.API.SandboxesController`: account-admin API under
  `/api/accounts/:account_handle/sandboxes` (agent environments,
  including `PATCH agent-environments/:id` for the API key, model and
  system prompt; sandboxes, exec/pause/resume/delete).
- `TuistWeb.API.AgentSessionsController`: account-admin API under
  `/api/accounts/:account_handle/sandboxes/agent-sessions` (create,
  list, show with live status and usage, `messages`, `events?after=n`,
  `archive`).

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Node daemon and protocol: `infra/sandboxd/AGENTS.md`
- Data export requirements: `server/data-export.md`
