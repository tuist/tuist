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
  state; `shutdown/1` releases it; the rest are I/O primitives. Tools dispatch
  through this module's facade (`Condukt.Sandbox.read/2`, `.exec/3`, etc.) so
  custom sandboxes work with every built-in tool automatically.

  ## Tool authoring rule

  If your tool reads or writes files, or runs subprocesses, route through the
  `Condukt.Sandbox.*` facade rather than calling `File.*`, `System.cmd/3`, or
  `MuonTrap.cmd/3` directly. Direct calls bypass the sandbox and break the
  ability to swap one in. Tools that touch unrelated systems (HTTP APIs,
  databases, in-process state) have nothing to sandbox and are unaffected.
  """

  defstruct [:module, :state, :opts]

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
  Searches file contents for `pattern` (regex). Options:

    * `:path` — directory to search (default: cwd)
    * `:glob` — glob filter applied to file paths
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

  @optional_callbacks [mount: 3, grep: 3, glob: 3]

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

  def mount(%__MODULE__{module: module, state: state}, host_path, vfs_path) do
    if function_exported?(module, :mount, 3) do
      module.mount(state, host_path, vfs_path)
    else
      {:error, :not_supported}
    end
  end

  def cwd(%__MODULE__{module: module, state: state}), do: module.cwd(state)
end
