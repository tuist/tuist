# Sandboxes (Context)

Server control plane for the Firecracker sandboxes run by `sandboxd`
(`infra/sandboxd/AGENTS.md` is the protocol and lifecycle spec). One
sandbox is one persistent microVM per coding-agent session; the first
consumer is Claude Managed Agents `self_hosted` environments.

## Pieces

- `Tuist.Sandboxes`: context over `sandboxes` and
  `sandbox_agent_environments`; every state transition maps to one node
  command (`create`, `resume`, `pause`, `delete`, `exec`, `start_worker`).
  `handle_node_event/2` and `reconcile_node_report/2` absorb what the
  node reports back.
- `Tuist.Sandboxes.Nodes`: `Registry` of connected nodes (name to socket
  pid plus capacity/templates/sandboxes) and `call/4`, the blocking
  request/response bridge onto `TuistWeb.SandboxNodeWebSock`, with
  `on_stream` for `exec` output.
- `Tuist.Sandboxes.Anthropic.Client`: Req client for the work queue
  (`poll`, `ack`, `stop`, `stats`), authenticated with the environment
  key. `TUIST_ANTHROPIC_API_URL` overrides the base URL.
- `Tuist.Sandboxes.Anthropic.Supervisor`: registry + task supervisor +
  dynamic supervisor of one `Poller` per enabled agent environment, kept
  in sync with the table by `Manager` every 30s. Started on web pods
  outside tests (`sandboxes_children/0` in `Tuist.Application`).
- `Tuist.Sandboxes.Router`: finds or creates the session's sandbox,
  resumes it, records the residency and starts `sbx-worker` with the
  session credentials; force-stops the work item on any failure so
  Anthropic re-queues it.
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
- `Nodes.call/4` must never run on the socket process itself (it waits
  on a message that process has to deliver); report handling spawns
  orphan deletes via `Tuist.Tasks.run_async/1`.

## Web layer

- `TuistWeb.SandboxNodesController` (`GET /api/internal/sandboxes/nodes/connect`):
  TokenReview with the `tuist-sandboxes` audience, namespace check,
  `X-Tuist-Node-Name`, WebSocket upgrade to `TuistWeb.SandboxNodeWebSock`.
- `TuistWeb.API.SandboxesController`: account-admin API under
  `/api/accounts/:account_handle/sandboxes` (agent environments,
  sandboxes, exec/pause/resume/delete).

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Node daemon and protocol: `infra/sandboxd/AGENTS.md`
- Data export requirements: `server/data-export.md`
