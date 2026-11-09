# Remote Runtime Investigation

## Current state

Condukt sessions are local-only today.

- `Condukt.Session` stores a local `cwd` and passes it into tool context.
- `Condukt.Tools.Bash` executes `bash -c ...` locally through `MuonTrap`.
- `Condukt.Tools.Read`, `Condukt.Tools.Write`, and `Condukt.Tools.Edit` operate directly on the local filesystem.

That means the agent loop already has a clean tool boundary, but the built-in tools assume the BEAM host is the execution environment.

## Goal

Run a session inside an isolated remote environment that can be:

- created on demand
- bootstrapped with repo contents and dependencies
- used for file operations and command execution during the run
- exposed when needed through a browser terminal or preview URL
- shut down automatically after the session finishes or goes idle

## Recommended architecture

Add a runtime abstraction below the tools rather than creating provider-specific tools.

### 1. Introduce a runtime behaviour

Add a new behaviour, for example `Condukt.Runtime`, responsible for environment lifecycle and remote I/O:

- `create_session(opts) :: {:ok, session}`
- `destroy_session(session) :: :ok | {:error, term()}`
- `exec(session, command, opts) :: {:ok, %{output: binary(), exit_code: integer()}} | {:error, term()}`
- `read_file(session, path, opts) :: {:ok, binary() | %{type: :image, ...}} | {:error, term()}`
- `write_file(session, path, content, opts) :: {:ok, term()} | {:error, term()}`
- `file_info(session, path) :: {:ok, map()} | {:error, term()}`
- `mkdir_p(session, path) :: :ok | {:error, term()}`
- `delete_session_command(session, id)` or PTY/session callbacks if interactive processes matter

The existing local behavior becomes `Condukt.Runtime.Local`, implemented with `File` and `MuonTrap`.

### 2. Move tool implementations onto the runtime

Built-in tools should stop calling `File.*` and `MuonTrap` directly.

Instead:

- `Read` calls `runtime.read_file/3`
- `Write` calls `runtime.mkdir_p/2` and `runtime.write_file/4`
- `Edit` can remain a text replacement tool, but should read and write through the runtime
- `Bash` calls `runtime.exec/3`

This keeps the LLM-facing tool set unchanged while making execution local or remote depending on session config.

### 3. Store runtime session in `Condukt.Session`

Session state should carry both the runtime module and the provisioned runtime session:

- `:runtime` - behaviour implementation
- `:runtime_opts` - provider-specific configuration
- `:runtime_session` - provider session/sandbox reference
- `:cwd` - interpreted as workspace root inside the runtime

At `start_link/2`, Condukt can either:

- create the runtime session immediately, or
- lazily create it on first tool call

For sessions that may never use tools, lazy creation is safer and cheaper.

## Provider evaluation

### Daytona

Best first target.

Why it fits:

- Daytona exposes direct API endpoints for sandbox create/start/stop/delete.
- Daytona documents command execution with cwd, timeout, and env support.
- Daytona has file system tooling, PTY support, process sessions, previews, and snapshot-based bootstrapping.
- Daytona supports auto-stop, auto-archive, and auto-delete lifecycle controls.
- Daytona docs show a public HTTP API, so Elixir can integrate through `Req` without introducing a Python or Node sidecar.

Implication:

- Condukt can implement `Condukt.Runtime.Daytona` as a direct Elixir HTTP client.
- This is the cleanest path if the goal is “plug account credentials into Condukt and run sessions remotely.”

Recommended usage model:

1. Create sandbox from a snapshot or image.
2. Sync workspace into the sandbox or clone the repo in-sandbox.
3. Set sandbox root as session `cwd`.
4. Route all built-in tools through the Daytona runtime.
5. Stop or delete the sandbox on completion.

### E2B

Strong second option, especially for agent workloads.

Why it fits:

- E2B exposes sandbox command execution, filesystem APIs, PTY support, and pause/resume-style lifecycle controls.
- It is explicitly positioned for agent sandboxes and isolated code execution.
- Custom templates are useful for warm starts.

Constraint:

- The official docs are SDK-centric. I did not find a clear public REST API in the docs surfaced here.
- That makes Elixir integration less direct than Daytona unless we either:
  - call a small Node/Python bridge service, or
  - rely on an E2B CLI wrapper from `MuonTrap`, which is weaker than a native client

Implication:

- E2B is viable, but I would not make it the first in-process Elixir integration target unless a stable HTTP API is confirmed.

### Modal

Useful, but not the best first fit for Condukt itself.

Why it fits:

- Modal Sandboxes support arbitrary commands, file operations, tunnels, snapshots, custom images, volumes, idle timeouts, and secure networking controls.
- It is powerful for running full app previews and heavier compute workloads.

Constraint:

- Modal is still primarily SDK-driven, with Python as the main control surface and JS/Go support still catching up.
- I did not find a documented generic REST control plane for sandbox lifecycle and command execution comparable to Daytona's public API.
- In practice, Elixir integration would likely mean operating a small Python or JS control service that Condukt talks to.

Implication:

- Modal is a good backend if you are comfortable owning an extra service boundary.
- It is not the simplest first-party Elixir adapter.

## Recommended implementation order

### Phase 1: Runtime abstraction

Add:

- `Condukt.Runtime`
- `Condukt.Runtime.Local`
- session config for `:runtime`, `:runtime_opts`, and lazy runtime creation

No behavior change yet.

### Phase 2: Move built-in tools to runtime-backed I/O

Refactor:

- `Condukt.Tools.Bash`
- `Condukt.Tools.Read`
- `Condukt.Tools.Write`
- `Condukt.Tools.Edit`

The public tool API stays the same.

### Phase 3: Daytona adapter

Implement `Condukt.Runtime.Daytona` with:

- sandbox lifecycle
- command execution
- file read/write
- optional PTY/session support
- cleanup hooks

This should be enough for the existing built-in coding tools to run remotely.

### Phase 4: Workspace bootstrapping

Support one or more workspace strategies:

- clone git repo inside the sandbox
- upload tarball of local workspace
- restore from provider snapshot/template
- mount a shared persistent volume for caches

For coding sessions, cloning the repo plus restoring caches is usually the best tradeoff.

### Phase 5: Operational controls

Add:

- idle timeout / auto-destroy
- sandbox labels and metadata
- telemetry around provision time and command latency
- explicit cleanup on session termination
- retry/recovery behavior for provider-side failures

## Important design decisions

### Prefer runtime adapters over provider-specific tools

Do not add `DaytonaRead`, `DaytonaWrite`, `DaytonaBash`, etc.

That would fragment the API surface and force agent authors to choose tools by infrastructure provider. The agent should use the same logical tools regardless of where the execution happens.

### Keep session state in one place

The remote environment should belong to the Condukt session, not to individual tool invocations.

If tools each provision their own sandbox, the session will lose filesystem/process continuity.

### Treat remote `cwd` as workspace root

Today `cwd` means a local directory. In the remote design, it should mean the root of the workspace inside the runtime environment.

That preserves the existing tool contract and keeps relative paths working.

### Interactive processes need a second interface

The current `Bash` tool is request/response. For package managers, REPLs, long-lived dev servers, and browser terminals, we will eventually need either:

- process sessions, or
- PTY streaming support

Daytona already has documented session and PTY concepts. E2B also exposes PTY support. Modal can expose long-lived processes and tunnels, but the orchestration model is less native for Elixir.

## Recommendation

Build the runtime abstraction now and target Daytona first.

That gives Condukt:

- the least invasive API change
- a direct Elixir integration path
- lifecycle controls that match “spin up, run a session, shut down”
- room to add E2B and Modal later without rewriting tools again

If you want Modal support too, I would treat it as a second integration path behind the same runtime behaviour, likely through a small Python or JS bridge service instead of a pure Elixir client.

## Sources

- Daytona Sandboxes: https://www.daytona.io/docs/en/sandboxes/
- Daytona Process and Code Execution: https://www.daytona.io/docs/en/process-code-execution/
- Daytona PTY: https://www.daytona.io/docs/en/pty
- E2B Docs: https://e2b.dev/docs
- E2B Sandbox lifecycle: https://e2b.dev/docs/sandbox
- E2B SDK reference: https://e2b.dev/docs/sdk-reference
- E2B file read/write: https://e2b.dev/docs/filesystem/read-write
- Modal Sandboxes guide: https://modal.com/docs/guide/sandbox
- Modal Sandbox reference: https://modal.com/docs/reference/modal.Sandbox
- Modal networking and security: https://modal.com/docs/guide/sandbox-networking
- Modal JS/Go SDKs: https://modal.com/docs/guide/sdk-javascript-go
