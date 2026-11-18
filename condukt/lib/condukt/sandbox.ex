defmodule Condukt.Sandbox do
  @moduledoc """
  Filesystem and process-execution capabilities exposed to tools.

  A sandbox is a runtime-swappable backend for the operations a tool needs to
  reach the outside world: read/write/edit files, run commands, glob, and grep.
  Built-in sandboxes:

  - `Condukt.Sandbox.Local` runs against the host filesystem and spawns real
    processes via `MuonTrap`.
  - `Condukt.Sandbox.Virtual` (in `:condukt_bashkit_nif`) runs inside an
    in-memory virtual filesystem and a Rust-implemented bash interpreter, with
    no host process spawning by default.
  - `Condukt.Sandbox.Microsandbox` boots a `microsandbox` microVM, bind-mounts
    selected host directories into it, and runs commands inside the guest.

  ## Why a sandbox

  Built-in tools (`Condukt.Tools.Read`, `Tools.Write`, `Tools.Edit`,
  `Tools.Bash`, `Tools.Glob`, `Tools.Grep`) are sandbox-agnostic: they declare
  one tool name and JSON schema to the LLM and route every primitive call
  through the active sandbox. This means the same agent definition can run
  against the host filesystem in development and against an isolated virtual
  filesystem in production by changing one option at `start_link/1`.

  ## Configuring

  Pass `:sandbox` at session start (or as the agent module's `sandbox/0`
  callback). Accepted forms:

      # module only — uses defaults (Local resolves :cwd to File.cwd!())
      sandbox: Condukt.Sandbox.Local

      # module + init opts
      sandbox: {Condukt.Sandbox.Local, cwd: "/path/to/project"}

      # already-initialized struct (advanced)
      sandbox: Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: "/tmp")

  When `:sandbox` is omitted, sessions default to
  `{Condukt.Sandbox.Local, cwd: <:cwd opt or File.cwd!()>}` so existing
  agents continue to behave as they did before sandboxes existed.

  ## Writing a custom sandbox

  Implement the `Condukt.Sandbox` behaviour. `init/1` builds the per-session
  state; `shutdown/1` releases it; the rest are I/O primitives. `glob/3`,
  `grep/3`, `list_dir/2`, `mount/3`, and the process callbacks are optional. Tools dispatch
  through this module's facade (`Condukt.Sandbox.read/2`, `.exec/3`, etc.) so
  custom sandboxes work with every built-in tool automatically.

  ## Processes that outlive their caller

  The optional `c:start_process/4`, `c:read_process/4`, and `c:stop_process/2`
  run a command under a stable id, apart from the BEAM process that started
  it: a caller reads its output from an offset as it runs, learns its exit
  status, and kills it, and anyone who knows the id finds it again.
  `Local`, `Kubernetes`, and `Microsandbox` implement them;
  `Condukt.Tools.Bash` uses them when they are there and `exec/3` otherwise.

  ## Tool authoring rule

  If your tool reads or writes files, or runs subprocesses, route through the
  `Condukt.Sandbox.*` facade rather than calling `File.*`, `System.cmd/3`, or
  `MuonTrap.cmd/3` directly. Direct calls bypass the sandbox and break the
  ability to swap one in. Tools that touch unrelated systems (HTTP APIs,
  databases, in-process state) have nothing to sandbox and are unaffected.
  """

  defstruct [:module, :state, :opts, :lease]

  @doc "Initializes per-session sandbox state."
  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, term()}

  @doc "Releases any resources held by the sandbox state."
  @callback shutdown(state :: term()) :: :ok

  @doc "Reads a file's raw bytes."
  @callback read_file(state :: term(), path :: binary()) :: {:ok, binary()} | {:error, term()}

  @doc "Writes raw bytes to a file, creating parent directories as needed."
  @callback write_file(state :: term(), path :: binary(), content :: binary()) :: :ok | {:error, term()}

  @doc """
  Replaces the unique occurrence of `old_text` with `new_text`.
  Returns the count of pre-edit occurrences alongside the post-edit content
  so callers can decide how to surface ambiguity or no-op edits.
  """
  @callback edit_file(state :: term(), path :: binary(), old_text :: binary(), new_text :: binary()) ::
              {:ok, %{occurrences: non_neg_integer(), content: binary()}}
              | {:error, term()}

  @doc """
  Runs a shell command. Options:

    * `:cwd` — working directory
    * `:env` — list of `{key, value}` strings to layer onto the base env
    * `:timeout` — milliseconds before the command is killed
  """
  @callback exec(state :: term(), command :: binary(), opts :: keyword()) ::
              {:ok, %{output: binary(), exit_code: integer()}} | {:error, :timeout | term()}

  @doc """
  Returns paths matching `pattern`. Options:

    * `:cwd` — base directory; pattern is resolved relative to it
    * `:limit` — maximum number of paths to return
  """
  @callback glob(state :: term(), pattern :: binary(), opts :: keyword()) ::
              {:ok, [binary()]} | {:error, term()}

  @doc """
  Lists the entries of the directory `path`, dotfiles included, each with
  whether it is a directory or anything else. Whether a symlink to a
  directory counts as one is the sandbox's choice: `Local` follows it, and a
  sandbox that confines files to a checkout can list it as a file. Returns
  `{:error, :enoent}` for a missing path and `{:error, :enotdir}` for one
  that is not a directory.

  Optional: `list_dir/2` falls back to a shell listing through `c:exec/3`.
  Implement it when the sandbox confines file access more than its shell.
  """
  @callback list_dir(state :: term(), path :: binary()) ::
              {:ok, [%{name: binary(), type: :directory | :file}]} | {:error, term()}

  @doc """
  Searches file contents for `pattern` (regex). Options:

    * `:path` — directory to search (default: cwd)
    * `:glob` — glob filter applied to file paths relative to `:path`; one
      without a `/`, such as `*.ex`, matches file names at any depth
    * `:case_sensitive` — defaults to true
    * `:limit` — maximum matches to return
  """
  @callback grep(state :: term(), pattern :: binary(), opts :: keyword()) ::
              {:ok, [%{path: binary(), line_number: pos_integer(), line: binary()}]}
              | {:error, term()}

  @doc """
  Mounts a host directory into the sandbox at `vfs_path`. Sandboxes that have
  no separate VFS (like `Local`) should return `{:error, :not_supported}`.
  """
  @callback mount(state :: term(), host_path :: binary(), vfs_path :: binary()) ::
              :ok | {:error, :not_supported | term()}

  @doc """
  Returns the effective working directory inside the sandbox.

  Used by project-instruction discovery and any caller that needs to address
  files relative to the sandbox's root without knowing which backend is in
  use.
  """
  @callback cwd(state :: term()) :: binary()

  @doc """
  Starts `command` as a process named `id` that runs on its own, apart from
  the BEAM process that started it, and returns at once.

  `id` is any string. Starting is idempotent on it: when the sandbox already
  holds a process under `id`, running or exited, it returns
  `{:error, :already_started}` and leaves it alone, so a caller that lost
  track of a process, such as a restarted session, finds it again by starting
  it again. Output goes to a log the sandbox keeps, combined stdout and
  stderr, until `c:stop_process/2`. Options are those of `c:exec/3`:

    * `:cwd` — working directory
    * `:env` — list of `{key, value}` strings to layer onto the base env
    * `:timeout` — milliseconds after which the sandbox kills the command and
      reports its status as `:timeout`

  and, where the sandbox supports them:

    * `:stdin` — `true` keeps the command's stdin open for
      `c:write_process/4`; otherwise it reads an empty stdin
    * `:pty` — `true` runs the command on a pseudo-terminal, as an
      interactive shell for a person needs (see `Condukt.Sandbox.Terminal`)
  """
  @callback start_process(state :: term(), id :: binary(), command :: binary(), opts :: keyword()) ::
              :ok | {:error, :already_started | term()}

  @doc """
  Reads a process's output from byte `offset`, and its status.

  With `:wait` (milliseconds), waits up to that long for output past
  `offset` or the process's end before answering, so a follower does not
  poll; a sandbox may answer sooner.

  Returns at most `:max_bytes` (default 64 KiB) as `output`, the `offset` to
  read from next, the `size` of the whole log so far, and `status`:

    * `:running`
    * `{:exited, exit_code}` — `exit_code` is `nil` when the process ended
      without the sandbox recording how, such as when its container restarted
    * `:timeout` — the sandbox killed it after its `:timeout`

  The status is taken before the output, so once it is not `:running`, the
  log is complete and reading up to `size` gets all of it. Returns
  `{:error, :not_found}` for an id the sandbox holds nothing for.
  """
  @callback read_process(state :: term(), id :: binary(), offset :: non_neg_integer(), opts :: keyword()) ::
              {:ok,
               %{
                 output: binary(),
                 offset: non_neg_integer(),
                 size: non_neg_integer(),
                 status: :running | {:exited, integer() | nil} | :timeout
               }}
              | {:error, :not_found | term()}

  @doc """
  Kills a process if it still runs, with the processes it started, and
  discards its log and status. Stopping an unknown id returns `:ok`.
  """
  @callback stop_process(state :: term(), id :: binary()) :: :ok | {:error, term()}

  @doc """
  Appends `data` to the stdin of a process started with `stdin: true`.

  Options:

    * `:close` — end its stdin after this write
    * `:offset` — the bytes stdin held before this write. With it, a write
      sent again, such as after a lost reply, lands once: when stdin already
      ends with it the call returns `:ok` without appending, and when stdin
      holds anything else than `offset` bytes it returns
      `{:error, :offset_mismatch}`.

  Returns `{:error, :stdin_closed}` once stdin ended, and
  `{:error, :not_found}` for an unknown id.
  """
  @callback write_process(state :: term(), id :: binary(), data :: binary(), opts :: keyword()) ::
              :ok | {:error, :not_found | :stdin_closed | :offset_mismatch | term()}

  @doc """
  Asks the sandbox to deliver a process's end itself, as
  `Condukt.signal(session_id, signal, key, status)`, where `status` is what
  `c:read_process/4` reports once it is no longer `:running`.

  Return `:ok` only when the delivery survives the BEAM process, and the
  node, that asked for it, such as when the sandbox's own control plane
  watches the process. A parked `Condukt.Tools.Bash` call then wakes even
  after a deploy restarted the node its watcher ran on. A process that has
  already ended is delivered at once.
  """
  @callback watch_process(
              state :: term(),
              id :: binary(),
              target :: %{session_id: binary(), signal: module(), key: binary()}
            ) ::
              :ok | {:error, term()}

  @doc """
  Tells the sandbox whether a session needs it.

  A session calls it with `:active` when a turn starts, again every
  `:lease_interval` milliseconds while the turn runs or is parked, and with
  `:idle` when the turn ends, however it ends. A sandbox that bills, pauses,
  or reaps idle machines maps these onto its lease: Tuist's onto a residency,
  `Kubernetes` onto its pod heartbeat. Errors are logged and otherwise
  ignored; the turn goes on.
  """
  @callback activity(state :: term(), activity :: :active | :idle) :: :ok | {:error, term()}

  @doc """
  Saves the sandbox's disks so a later sandbox can boot from them, and
  returns an id that the sandbox's `init/1` takes as `:snapshot`. See
  `Condukt.Sandbox.Setup` for the preparation phase that uses it.
  """
  @callback snapshot(state :: term(), opts :: keyword()) :: {:ok, snapshot_id :: binary()} | {:error, term()}

  @doc """
  Makes `port` inside the sandbox reachable from outside it and returns the
  URL, as a supervised service's portal. Options are the sandbox's own, such
  as who may open the URL.
  """
  @callback expose_port(state :: term(), port :: pos_integer(), opts :: keyword()) ::
              {:ok, url :: binary()} | {:error, term()}

  @optional_callbacks [
    list_dir: 2,
    mount: 3,
    grep: 3,
    glob: 3,
    start_process: 4,
    read_process: 4,
    stop_process: 2,
    write_process: 4,
    watch_process: 3,
    activity: 2,
    snapshot: 2,
    expose_port: 3
  ]

  # ============================================================================
  # Construction & resolution
  # ============================================================================

  @doc """
  Constructs a sandbox handle by initializing `module` with `opts`.

  Returns `{:ok, sandbox}` so callers can surface init failures (an in-memory
  sandbox that fails to allocate, a virtual sandbox whose NIF refused to
  start, etc).
  """
  def new(module, opts \\ []) when is_atom(module) do
    case module.init(opts) do
      {:ok, state} -> {:ok, %__MODULE__{module: module, state: state, opts: opts}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Normalizes a user-supplied `:sandbox` option into a `t()`.

  Accepts an already-built struct, a bare module, or a `{module, opts}` tuple.
  Returns `{:ok, sandbox}` or `{:error, reason}`.
  """
  def resolve(%__MODULE__{} = sandbox), do: {:ok, sandbox}
  def resolve(module) when is_atom(module), do: new(module, [])
  def resolve({module, opts}) when is_atom(module) and is_list(opts), do: new(module, opts)
  def resolve(other), do: {:error, {:invalid_sandbox, other}}

  @doc "Releases the sandbox state."
  def shutdown(%__MODULE__{module: module, state: state}), do: module.shutdown(state)

  # ============================================================================
  # Primitive facade — what tools call
  # ============================================================================

  def read(%__MODULE__{module: module, state: state}, path), do: module.read_file(state, path)

  def write(%__MODULE__{module: module, state: state}, path, content), do: module.write_file(state, path, content)

  def edit(%__MODULE__{module: module, state: state}, path, old_text, new_text),
    do: module.edit_file(state, path, old_text, new_text)

  def exec(%__MODULE__{module: module, state: state}, command, opts \\ []), do: module.exec(state, command, opts)

  def glob(%__MODULE__{module: module, state: state}, pattern, opts \\ []) do
    if function_exported?(module, :glob, 3) do
      module.glob(state, pattern, opts)
    else
      {:error, :not_supported}
    end
  end

  def grep(%__MODULE__{module: module, state: state}, pattern, opts \\ []) do
    if function_exported?(module, :grep, 3) do
      module.grep(state, pattern, opts)
    else
      {:error, :not_supported}
    end
  end

  @doc """
  Lists a directory's entries. See `c:list_dir/2`. Sandboxes that do not
  implement it list through `exec/3` with a POSIX shell script.
  """
  def list_dir(%__MODULE__{module: module, state: state} = sandbox, path) do
    if supports?(sandbox, :list_dir, 2) do
      module.list_dir(state, path)
    else
      list_dir_with_shell(sandbox, path)
    end
  end

  # Exit 3 and 4 tell a missing path from one that is not a directory. Each
  # entry is printed as `d/name` or `f/name`; `[ -e ] || [ -L ]` drops an
  # unmatched glob, which stays literal without nullglob.
  @list_dir_script ~S"""
  [ -e "$dir" ] || exit 3
  [ -d "$dir" ] || exit 4
  cd "$dir" || exit 3
  for p in * .*; do
    case "$p" in .|..) continue ;; esac
    [ -e "$p" ] || [ -L "$p" ] || continue
    if [ -d "$p" ]; then printf 'd/%s\n' "$p"; else printf 'f/%s\n' "$p"; fi
  done
  """

  defp list_dir_with_shell(sandbox, path) do
    # bashkit's `cd` takes no `--`, so a path that looks like an option is
    # made relative instead.
    path = if String.starts_with?(path, "-"), do: "./" <> path, else: path

    command = "dir='" <> String.replace(path, "'", "'\\''") <> "'\n" <> @list_dir_script

    case exec(sandbox, command, timeout: 30_000) do
      {:ok, %{exit_code: 0, output: output}} ->
        entries =
          for <<kind, ?/, name::binary>> <- String.split(output, "\n", trim: true) do
            %{name: name, type: if(kind == ?d, do: :directory, else: :file)}
          end

        {:ok, entries}

      {:ok, %{exit_code: 3}} ->
        {:error, :enoent}

      {:ok, %{exit_code: 4}} ->
        {:error, :enotdir}

      {:ok, %{output: output}} ->
        {:error, String.trim(output)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  # For sandboxes that grep with `Path.wildcard/2` or a shell glob: a file
  # glob without a `/` matches file names at any depth, as `c:grep/3` says.
  def grep_file_glob(glob), do: if(String.contains?(glob, "/"), do: glob, else: "**/" <> glob)

  def mount(%__MODULE__{module: module, state: state}, host_path, vfs_path) do
    if function_exported?(module, :mount, 3) do
      module.mount(state, host_path, vfs_path)
    else
      {:error, :not_supported}
    end
  end

  def cwd(%__MODULE__{module: module, state: state}), do: module.cwd(state)

  @doc """
  Whether the sandbox runs processes apart from their caller, through
  `start_process/4`, `read_process/4`, and `stop_process/2`.
  """
  def processes?(%__MODULE__{module: module}) do
    Code.ensure_loaded?(module) and function_exported?(module, :start_process, 4) and
      function_exported?(module, :read_process, 4) and function_exported?(module, :stop_process, 2)
  end

  @doc "Starts a process named `id`. See `c:start_process/4`."
  def start_process(%__MODULE__{} = sandbox, id, command, opts \\ []) when is_binary(id) do
    if processes?(sandbox),
      do: sandbox.module.start_process(sandbox.state, id, command, opts),
      else: {:error, :not_supported}
  end

  @doc "Reads a process's output from `offset`, and its status. See `c:read_process/4`."
  def read_process(%__MODULE__{} = sandbox, id, offset, opts \\ []) when is_binary(id) do
    if processes?(sandbox),
      do: sandbox.module.read_process(sandbox.state, id, offset, opts),
      else: {:error, :not_supported}
  end

  @doc "Kills a process and discards its log. See `c:stop_process/2`."
  def stop_process(%__MODULE__{} = sandbox, id) when is_binary(id) do
    if processes?(sandbox), do: sandbox.module.stop_process(sandbox.state, id), else: {:error, :not_supported}
  end

  @doc "Writes to a process's stdin. See `c:write_process/4`."
  def write_process(%__MODULE__{} = sandbox, id, data, opts \\ []) when is_binary(id) and is_binary(data),
    do: optional(sandbox, :write_process, [id, data, opts])

  @doc "Asks the sandbox to deliver a process's end. See `c:watch_process/3`."
  def watch_process(%__MODULE__{} = sandbox, id, %{session_id: _, signal: _, key: _} = target) when is_binary(id),
    do: optional(sandbox, :watch_process, [id, target])

  @doc "Tells the sandbox whether a session needs it. See `c:activity/2`."
  def activity(%__MODULE__{} = sandbox, activity) when activity in [:active, :idle],
    do: optional(sandbox, :activity, [activity])

  @doc "Saves the sandbox's disks for later sandboxes to boot from. See `c:snapshot/2`."
  def snapshot(%__MODULE__{} = sandbox, opts \\ []), do: optional(sandbox, :snapshot, [opts])

  @doc "Exposes a port in the sandbox and returns its URL. See `c:expose_port/3`."
  def expose_port(%__MODULE__{} = sandbox, port, opts \\ []) when is_integer(port) and port > 0,
    do: optional(sandbox, :expose_port, [port, opts])

  @doc """
  Streams the directory `path` out of the sandbox as a tar archive, in
  chunks, without holding it in memory. See `Condukt.Sandbox.Transfer`.
  """
  defdelegate export(sandbox, path, opts \\ []), to: Condukt.Sandbox.Transfer

  @doc """
  Unpacks a tar archive, an enumerable of chunks such as `export/3` returns,
  into the directory `path` in the sandbox. See `Condukt.Sandbox.Transfer`.
  """
  defdelegate import_archive(sandbox, path, chunks, opts \\ []), to: Condukt.Sandbox.Transfer

  @doc "Whether the sandbox implements the optional callback `name/arity`."
  def supports?(%__MODULE__{module: module}, name, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, name, arity)
  end

  defp optional(%__MODULE__{module: module, state: state} = sandbox, name, args) do
    if supports?(sandbox, name, length(args) + 1),
      do: apply(module, name, [state | args]),
      else: {:error, :not_supported}
  end
end
