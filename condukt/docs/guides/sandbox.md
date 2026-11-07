# Sandbox

A sandbox is a runtime-swappable backend for the operations a tool needs to
reach the outside world: read or write files, run shell commands, glob files,
search file contents. Built-in tools like `Condukt.Tools.Read` and
`Condukt.Tools.Bash` declare one tool name and JSON schema to the LLM and
route every primitive call through the active sandbox. The same agent
definition can therefore run against the host filesystem in development and
against an isolated virtual filesystem, a microVM guest, or a remote pod in
production by changing one option at session start.

## Built-in sandboxes

* `Condukt.Sandbox.Local` is the default. It operates against the host
  filesystem and spawns real bash subprocesses via `MuonTrap`.
* `Condukt.Sandbox.Virtual` runs against an in-memory virtual filesystem and
  a Rust-implemented bash interpreter (bashkit), with no host process
  spawning by default. It is shipped via a precompiled NIF, so consumers
  do not need a Rust toolchain to use it.
* `Condukt.Sandbox.Microsandbox` boots a
  [microsandbox](https://github.com/superradcompany/microsandbox) microVM,
  bind-mounts host paths into the guest at sandbox creation time, and routes
  reads, writes, and commands through the guest agent bridge.
* `Condukt.Sandbox.Kubernetes` runs each session inside a dedicated
  Kubernetes pod. All filesystem reads, writes, and process execution
  happen inside the pod via the Kubernetes exec API; the agent cannot
  reach the host running the Condukt BEAM process.

Custom sandboxes implement the `Condukt.Sandbox` behaviour and plug in the
same way.

## Virtual sandbox

`Condukt.Sandbox.Virtual` is backed by [bashkit](https://github.com/everruns/bashkit),
a virtual bash interpreter with an in-memory filesystem written in Rust. It
is loaded into the BEAM via a Rustler NIF.

```elixir
# Empty in-memory filesystem.
{:ok, sb} = Condukt.Sandbox.new(Condukt.Sandbox.Virtual)
{:ok, %{output: "hi\n", exit_code: 0}} = Condukt.Sandbox.exec(sb, "echo hi")

# Mount the host project at /workspace, read-only:
{:ok, sb} =
  Condukt.Sandbox.new(Condukt.Sandbox.Virtual,
    mounts: [{File.cwd!(), "/workspace", :readonly}]
  )

{:ok, contents} = Condukt.Sandbox.read(sb, "/workspace/mix.exs")

# Or mount at runtime:
:ok = Condukt.Sandbox.mount(sb, "/path/on/host", "/extra")
```

Each `exec/3` call is stateless: `cd`, `export`, and shell variables do
not persist across calls. This matches `Sandbox.Local`'s contract and
lets the `Condukt.Tools.Bash` tool behave identically in both sandboxes.

The precompiled NIF is built and attached to GitHub releases for the
following targets:

```
aarch64-apple-darwin
aarch64-unknown-linux-gnu
x86_64-apple-darwin
x86_64-pc-windows-msvc
x86_64-unknown-linux-gnu
```

Compile in `MIX_ENV=dev` (and have a Rust toolchain installed) to build the
NIF from source. Other Mix environments download the precompiled artifact.
The release workflow publishes from `MIX_ENV=prod`, so package validation uses
the same precompiled path as Hex consumers.

### Sandbox-specific tools

`Condukt.Sandbox.Virtual.Tools.Mount` lets the agent mount a host
directory into the virtual filesystem at runtime. It only makes sense
with the Virtual sandbox; against `Sandbox.Local` it returns a clear
"not supported" error.

```elixir
def tools do
  Condukt.Tools.coding_tools() ++ [Condukt.Sandbox.Virtual.Tools.Mount]
end
```

## Microsandbox

`Condukt.Sandbox.Microsandbox` is backed by the
[microsandbox](https://github.com/superradcompany/microsandbox) crate. Condukt
loads it through a Rustler NIF and keeps a per-session async runtime alive so
the guest bridge can serve file and exec requests across the whole session.

```elixir
{:ok, sb} =
  Condukt.Sandbox.new(Condukt.Sandbox.Microsandbox,
    image: "ubuntu:24.04"
  )

{:ok, %{output: out, exit_code: 0}} = Condukt.Sandbox.exec(sb, "pwd")
String.trim(out) == "/workspace"

{:ok, sb} =
  Condukt.Sandbox.new(Condukt.Sandbox.Microsandbox,
    image: "ghcr.io/myorg/elixir-dev:latest",
    cwd: "/repo",
    workspace_host: File.cwd!(),
    mounts: [{"/tmp/cache", "/cache", :readwrite}]
  )
```

By default the sandbox bind-mounts the current host working directory at
`/workspace` and uses `/bin/bash` for `exec/3`. That gives the coding tools a
guest environment while still pointing at the host project tree.

Current limits:

* Runtime `mount/3` is not supported. `microsandbox` volumes are configured at
  sandbox creation time, so use the `:mounts` init option.
* `glob/3` and `grep/3` are available for host-backed bind mounts. Paths that
  only exist inside the guest rootfs return `{:error, :not_supported}`.
* `Condukt.Sandbox.NetworkPolicy` is still Kubernetes-only. Microsandbox does
  not translate that layer yet.

The precompiled NIF currently targets:

```
aarch64-apple-darwin
aarch64-unknown-linux-gnu
x86_64-unknown-linux-gnu
```

Unsupported hosts compile the Elixir wrapper as stubs that return
`{:error, :unsupported_target}`.

## Kubernetes sandbox

`Condukt.Sandbox.Kubernetes` creates one pod per session and routes every
filesystem and process primitive through the Kubernetes exec API. It uses
the [`:k8s`](https://hex.pm/packages/k8s) library and talks to the API
server over HTTPS, so no `kubectl` binary is required.

```elixir
# Minimal: uses the current kubeconfig context and the "default" namespace.
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: "...",
    sandbox: Condukt.Sandbox.Kubernetes
  )

# Production: pinned image, namespace, resource limits, RBAC.
sandbox = {
  Condukt.Sandbox.Kubernetes,
  image: "ghcr.io/myorg/agent-runtime:v1.4.2",
  namespace: "agents",
  context: "prod-cluster",
  service_account: "condukt-agent",
  resources: %{
    requests: %{cpu: "500m", memory: "1Gi"},
    limits: %{cpu: "2", memory: "4Gi"}
  },
  active_deadline_seconds: 4 * 3600,
  heartbeat_interval: 60_000,
  workspace_source: [git: "https://github.com/myorg/repo.git", ref: "main"],
  labels: %{"tenant" => "acme"},
  cwd: "/workspace"
}
```

### Decoupled pod lifecycle via the session id

The Kubernetes sandbox is idempotent on a stable id and decouples the pod
lifecycle from any single BEAM process. The session id (passed as `:id` to
`start_link/1`, or auto-generated) flows into the sandbox by default, so
the same value drives the session and the pod. `init/1` derives a
deterministic pod name from it and either adopts an existing pod or creates
a fresh one. This is the recommended pattern when an Oban-style worker
manages the session: a job retry passes the same id through, the sandbox
reattaches to the existing pod, and any state already on disk (a cloned
repo, in-progress edits) is preserved.

```elixir
defmodule MyApp.AgentWorker do
  use Oban.Worker, queue: :agents, max_attempts: 3

  @impl true
  def perform(%Oban.Job{id: job_id, args: %{"prompt" => prompt}}) do
    {:ok, agent} =
      MyApp.CodingAgent.start_link(
        id: job_id,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        sandbox: {Condukt.Sandbox.Kubernetes, namespace: "agents"},
        session_store: Condukt.SessionStore.Disk
      )

    Condukt.Session.run(agent, prompt)
  end
end
```

The pattern above pairs three things keyed on the same id: the pod (so the
workspace state survives across retries), the session snapshot in
`SessionStore.Disk` (so the conversation history survives), and the
heartbeat that keeps the pod alive while a worker is using it. A retry that
re-enters `perform/1` with the same `job_id` reattaches to the pod and
restores the session messages from the on-disk snapshot. Without a session
store, the pod survives but the conversation starts over.

Pass `:id` explicitly to the sandbox spec only when you want the pod
identity to diverge from the session identity (for example, a single
long-running pod shared across multiple sessions). An explicit value on the
sandbox spec wins over the session-supplied default.

When an id is in play, `shutdown/1` is a no-op by default and the pod
outlives the BEAM process. When the session is truly done, the caller
deletes the pod explicitly:

```elixir
Condukt.Sandbox.Kubernetes.terminate(job_id, namespace: "agents")
```

When no id is supplied at the session level, one is generated and the pod
follows the usual single-use lifecycle: `shutdown/1` deletes it.

### Project instructions inside the sandbox

`AGENTS.md`, `CLAUDE.md`, and `.agents/skills/*/SKILL.md` are read through
the active sandbox at session start, not from the host filesystem
directly. For `Sandbox.Local` that is the same place either way. For
`Sandbox.Virtual`, `Sandbox.Microsandbox`, and `Sandbox.Kubernetes` it means
the discovery finds files in the sandbox: a virtual filesystem with mounts, a
bind-mounted guest workspace, or a workspace inside a pod cloned via
`:workspace_source`. The agent picks up the same project instructions
regardless of which backend it is running against.

### State persistence

Each pod gets an `emptyDir` volume mounted at the session cwd
(`/workspace` by default). With `restartPolicy: Always`, K8s restarts the
container on crash and the volume survives, so a cloned repo or
in-progress file edits persist across container restarts within the same
pod. The volume does not survive pod deletion or node loss; for cross-node
durability, build an image that mounts a PersistentVolumeClaim.

`write_file/3` streams file contents through the Kubernetes exec stdin
channel. That keeps large writes out of the exec command line and avoids
the old base64 command-size ceiling.

Pass `:workspace_source` to clone a git repository into the workspace when
the pod is initialized:

```elixir
sandbox = {
  Condukt.Sandbox.Kubernetes,
  image: "ghcr.io/myorg/agent-runtime-with-git:v1",
  namespace: "agents",
  workspace_source: [
    git: "https://github.com/myorg/repo.git",
    ref: "main"
  ]
}
```

The clone runs inside the pod, so the runtime image must include `git`.
For stable `:id` sessions, an existing git checkout is reused and the
configured ref is checked out again on reattach.

### Stale pod handling

When `init/1` adopts an existing pod, it accepts `Running`, waits on
`Pending`, and waits for terminating pods to be deleted before recreating.
On `Succeeded` or `Failed` (which the keepalive container should not
normally produce) it returns `{:error, {:stale_pod, phase}}` by default
so the caller can decide what to do. Pass `on_stale: :recreate` to delete
and recreate automatically.

Each pod also carries a `condukt.tuist.dev/heartbeat-at` annotation. By default,
the sandbox starts a worker tied to the owner process that refreshes it
every 60 seconds. If the owning Condukt process crashes, the worker dies
too, and a separate process can reap stale pods before
`activeDeadlineSeconds` expires:

```elixir
{:ok, deleted_pods} =
  Condukt.Sandbox.Kubernetes.reap_stale(
    namespace: "agents",
    stale_after: 15 * 60_000
  )
```

Pass `heartbeat_interval: false` when you want to drive heartbeats from
your own process. In that case call `Condukt.Sandbox.Kubernetes.heartbeat/1`
with the sandbox handle or state.

### Hard ceiling on pod lifetime

Every pod is created with `activeDeadlineSeconds` (default 8 hours).
This is K8s-side insurance against truly abandoned pods: even if Condukt
crashes and forgets the pod, the cluster reclaims it.

### Auth resolution

Connection auth is resolved in this order:

1. The `:conn` opt, if you build a `K8s.Conn` yourself.
2. The in-cluster ServiceAccount token at
   `/var/run/secrets/kubernetes.io/serviceaccount/` when
   `KUBERNETES_SERVICE_HOST` is set or `in_cluster: true` is passed.
3. A kubeconfig file at `:kubeconfig` (or `$KUBECONFIG`, or
   `~/.kube/config`), using `:context` if supplied.

### RBAC

The identity Condukt runs as needs permission to create, get, exec into,
patch, list, and delete pods in the target namespace:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: condukt-sandbox
  namespace: agents
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "create", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: condukt-sandbox
  namespace: agents
subjects:
  - kind: ServiceAccount
    name: condukt
    namespace: agents
roleRef:
  kind: Role
  name: condukt-sandbox
  apiGroup: rbac.authorization.k8s.io
```

### Limitations

* `mount/3` is unsupported. K8s pods cannot accept new volumes once
  running. Mounts must be declared up front; in v1 that means baking a
  PVC into a custom image.
* `:workspace_source` requires `git` inside the runtime image. The default
  `debian:bookworm-slim` image is intentionally minimal and does not include
  development tools.

## Picking a sandbox

Sessions resolve the sandbox in this order:

1. The `:sandbox` option passed to `start_link/1`.
2. The agent module's `sandbox/0` callback, if defined.
3. Default: `{Condukt.Sandbox.Local, cwd: <:cwd option or File.cwd!()>}`.

```elixir
# Default: Local sandbox rooted at the host cwd.
{:ok, agent} = MyApp.CodingAgent.start_link(api_key: "...")

# Local sandbox rooted at a specific directory.
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: "...",
    sandbox: {Condukt.Sandbox.Local, cwd: "/path/to/project"}
  )

# Virtual sandbox (when condukt_bashkit_nif is installed).
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: "...",
    sandbox: Condukt.Sandbox.Virtual
  )

# Microsandbox backed by a guest image and the current workspace mount.
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: "...",
    sandbox: {Condukt.Sandbox.Microsandbox, image: "ubuntu:24.04"}
  )
```

Or declare a default on the agent module:

```elixir
defmodule MyApp.CodingAgent do
  use Condukt

  @impl true
  def sandbox do
    {Condukt.Sandbox.Local, cwd: "/path/to/project"}
  end
end
```

## Sandbox-aware tools

If you write a custom tool that touches the filesystem or spawns processes,
route through the `Condukt.Sandbox.*` facade rather than calling `File.*`,
`System.cmd/3`, or `MuonTrap.cmd/3` directly. Direct calls bypass the
sandbox and break the ability to swap one in.

The facade:

```elixir
Condukt.Sandbox.read(sandbox, path)
Condukt.Sandbox.write(sandbox, path, content)
Condukt.Sandbox.edit(sandbox, path, old_text, new_text)
Condukt.Sandbox.exec(sandbox, command, opts)
Condukt.Sandbox.glob(sandbox, pattern, opts)
Condukt.Sandbox.grep(sandbox, pattern, opts)
Condukt.Sandbox.mount(sandbox, host_path, vfs_path)
```

The sandbox is in `context.sandbox` when your tool's `call/2` is invoked.
See the [Tools guide](tools.md) for an example.

## Writing a custom sandbox

Implement the `Condukt.Sandbox` behaviour. `init/1` builds the per-session
state, `shutdown/1` releases it, and the rest are I/O primitives:

```elixir
defmodule MyApp.S3Sandbox do
  @behaviour Condukt.Sandbox

  @impl true
  def init(opts), do: {:ok, %{bucket: opts[:bucket]}}

  @impl true
  def shutdown(_state), do: :ok

  @impl true
  def read_file(state, path), do: ExAws.S3.get_object(state.bucket, path) |> ExAws.request()

  # write_file/3, edit_file/4, exec/3, plus optional glob/3, grep/3, mount/3
end
```

`glob/3`, `grep/3`, and `mount/3` are optional callbacks. The facade returns
`{:error, :not_supported}` when a sandbox does not implement them.

## Why sandboxes

Two reasons.

First, isolation: in multi-tenant deployments you may not want every agent
to read or write the host filesystem unrestricted. A virtual sandbox lets
you mount only the directories an agent should see and bound everything
else.

Second, portability: the same agent definition runs in development against
the real project (Local) and in production against an in-memory snapshot
(Virtual) without any code changes. Tests can build an isolated sandbox per
case and tear it down without touching disk.
