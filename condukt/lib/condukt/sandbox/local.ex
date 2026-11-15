defmodule Condukt.Sandbox.Local do
  @moduledoc """
  Sandbox that operates against the host filesystem and host shell.

  This is the default sandbox. It carries a base `:cwd` (resolved at
  `init/1`) that all relative paths and command executions use as their root.

  `mount/3` is unsupported (the host filesystem is the sandbox).

  ## Initializing

      {:ok, sandbox} = Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: "/tmp")

  Options:

    * `:cwd` — base directory for paths and commands (default `File.cwd!/0`)
    * `:process_dir` — where `start_process/4` keeps each process's log and
      status (default `condukt-processes` in the system temporary directory)

  ## Processes

  `start_process/4` runs a command through `MuonTrap` in a process under
  Condukt's own supervisor, registered by the id, rather than in the caller.
  The command outlives the caller and is found again by its id on the same
  node, but not across a node restart: `MuonTrap` stops it with the node, as
  it stops every command this sandbox runs.
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Local.State
  alias Condukt.Sandbox.Processes

  @base_env %{
    "TERM" => "dumb",
    "PAGER" => "cat",
    "GIT_PAGER" => "cat"
  }
  @capture_script """
  exec > "$1" 2>&1
  exec bash -c "$2"
  """
  @safe_env_vars ~w(PATH HOME USER LOGNAME HOSTNAME SHELL LANG LC_ALL LC_CTYPE TZ TMPDIR TMP TEMP)

  # ============================================================================
  # Sandbox callbacks
  # ============================================================================

  @impl Sandbox
  def init(opts) do
    cwd =
      opts
      |> Keyword.get(:cwd)
      |> case do
        nil -> File.cwd!()
        path -> Path.expand(path)
      end

    process_dir =
      opts
      |> Keyword.get_lazy(:process_dir, fn -> Path.join(System.tmp_dir!(), "condukt-processes") end)
      |> Path.expand()

    {:ok, %State{cwd: cwd, process_dir: process_dir}}
  end

  @doc false
  def registry, do: Condukt.Sandbox.Local.Registry

  @impl Sandbox
  def shutdown(_state), do: :ok

  @impl Sandbox
  def cwd(%State{cwd: cwd}), do: cwd

  @impl Sandbox
  def read_file(%State{cwd: cwd}, path) do
    case File.read(resolve(path, cwd)) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Sandbox
  def write_file(%State{cwd: cwd}, path, content) do
    absolute = resolve(path, cwd)

    with :ok <- File.mkdir_p(Path.dirname(absolute)) do
      File.write(absolute, content)
    end
  end

  @impl Sandbox
  def edit_file(%State{cwd: cwd}, path, old_text, new_text) do
    absolute = resolve(path, cwd)

    with {:ok, content} <- File.read(absolute) do
      apply_edit(absolute, content, old_text, new_text)
    end
  end

  defp apply_edit(absolute, content, old_text, new_text) do
    case count_occurrences(content, old_text) do
      0 -> {:ok, %{occurrences: 0, content: content}}
      n when n > 1 -> {:ok, %{occurrences: n, content: content}}
      1 -> write_replacement(absolute, content, old_text, new_text)
    end
  end

  defp write_replacement(absolute, content, old_text, new_text) do
    {:ok, new_content} = replace_first(content, old_text, new_text)

    case File.write(absolute, new_content) do
      :ok -> {:ok, %{occurrences: 1, content: new_content}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Sandbox
  def exec(%State{cwd: cwd}, command, opts) do
    run_cwd = opts |> Keyword.get(:cwd) |> resolve_optional(cwd)
    timeout = Keyword.get(opts, :timeout, 120_000)
    env_overrides = Keyword.get(opts, :env, [])
    env = build_env(env_overrides)
    capture_path = capture_path()

    try do
      case MuonTrap.cmd("bash", ["-c", @capture_script, "condukt-capture", capture_path, command],
             cd: run_cwd,
             stderr_to_stdout: true,
             env: env,
             parallelism: false,
             timeout: timeout
           ) do
        {_output, :timeout} ->
          {:error, :timeout}

        {output, exit_code} ->
          {:ok, %{output: capture_output(capture_path, output), exit_code: exit_code}}
      end
    catch
      :error, error -> {:error, format_error(error)}
    after
      File.rm(capture_path)
    end
  end

  @impl Sandbox
  def glob(%State{cwd: cwd}, pattern, opts) do
    base = opts |> Keyword.get(:cwd) |> resolve_optional(cwd)
    full_pattern = Path.join(base, pattern)

    paths =
      full_pattern
      |> Path.wildcard(match_dot: true)
      |> Enum.sort()
      |> Enum.map(&Path.relative_to(&1, base))
      |> apply_limit(opts[:limit])

    {:ok, paths}
  end

  @impl Sandbox
  def grep(%State{cwd: cwd}, pattern, opts) do
    base = opts |> Keyword.get(:path) |> resolve_optional(cwd)
    case_sensitive? = Keyword.get(opts, :case_sensitive, true)
    file_glob = Keyword.get(opts, :glob, "**/*")
    limit = Keyword.get(opts, :limit, 1_000)

    with {:ok, regex} <- compile_regex(pattern, case_sensitive?) do
      candidates =
        base
        |> Path.join(file_glob)
        |> Path.wildcard(match_dot: false)
        |> Enum.filter(&File.regular?/1)

      matches =
        candidates
        |> Stream.flat_map(&scan_file(&1, regex, base))
        |> Enum.take(limit)

      {:ok, matches}
    end
  end

  # A process is a task under `Condukt.TaskSupervisor`, registered under its
  # directory, which the id names, that runs the command through MuonTrap with output going to a file
  # and writes the exit status to another once it ends. Registration is the
  # atomic step that makes starting idempotent; the status file is written
  # before the task unregisters, so a reader that finds neither knows the
  # task was killed.
  @impl Sandbox
  def start_process(%State{} = state, id, command, opts) do
    dir = process_path(state, id)

    if Registry.lookup(registry(), dir) != [] or File.exists?(Path.join(dir, "status")) do
      {:error, :already_started}
    else
      run_opts = [
        cd: opts |> Keyword.get(:cwd) |> resolve_optional(state.cwd),
        env: build_env(Keyword.get(opts, :env, [])),
        timeout: Keyword.get(opts, :timeout)
      ]

      caller = self()
      ref = make_ref()

      {:ok, pid} =
        Task.Supervisor.start_child(Condukt.TaskSupervisor, fn -> run_process(caller, ref, dir, command, run_opts) end)

      monitor = Process.monitor(pid)

      receive do
        {^ref, reply} ->
          Process.demonitor(monitor, [:flush])
          reply

        {:DOWN, ^monitor, :process, _pid, reason} ->
          {:error, reason}
      end
    end
  end

  @impl Sandbox
  def read_process(%State{} = state, id, offset, opts) do
    dir = process_path(state, id)
    max_bytes = Keyword.get(opts, :max_bytes, 64 * 1024)

    with {:ok, status} <- process_status(dir),
         {:ok, %File.Stat{size: size}} <- File.stat(Path.join(dir, "output")),
         {:ok, output} <- read_range(Path.join(dir, "output"), offset, min(max_bytes, max(size - offset, 0))) do
      {:ok, %{output: output, offset: offset + byte_size(output), size: size, status: status}}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Sandbox
  def stop_process(%State{} = state, id) do
    dir = process_path(state, id)

    case Registry.lookup(registry(), dir) do
      [{pid, _value}] ->
        # MuonTrap kills the command when the process that runs it dies.
        monitor = Process.monitor(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
        end

      [] ->
        :ok
    end

    case File.rm_rf(dir) do
      {:ok, _paths} -> :ok
      {:error, reason, _path} -> {:error, reason}
    end
  end

  defp run_process(caller, ref, dir, command, run_opts) do
    case Registry.register(registry(), dir, nil) do
      {:ok, _owner} ->
        output = Path.join(dir, "output")

        with :ok <- File.mkdir_p(dir),
             File.rm(Path.join(dir, "status")),
             :ok <- File.write(output, "") do
          send(caller, {ref, :ok})
          write_status(dir, run_command(command, output, run_opts))
        else
          {:error, reason} -> send(caller, {ref, {:error, reason}})
        end

      {:error, {:already_registered, _pid}} ->
        send(caller, {ref, {:error, :already_started}})
    end
  end

  defp run_command(command, output, run_opts) do
    {timeout, run_opts} = Keyword.pop(run_opts, :timeout)
    run_opts = [stderr_to_stdout: true, parallelism: false] ++ run_opts
    run_opts = if timeout, do: Keyword.put(run_opts, :timeout, timeout), else: run_opts

    case MuonTrap.cmd("bash", ["-c", @capture_script, "condukt-capture", output, command], run_opts) do
      {_output, :timeout} -> "timeout"
      {_output, exit_code} -> Integer.to_string(exit_code)
    end
  catch
    :error, error ->
      File.write(output, format_error(error), [:append])
      "127"
  end

  defp write_status(dir, status) do
    tmp = Path.join(dir, "status.tmp")
    File.write!(tmp, status)
    File.rename!(tmp, Path.join(dir, "status"))
  end

  defp process_status(dir) do
    cond do
      Registry.lookup(registry(), dir) != [] -> {:ok, :running}
      File.exists?(Path.join(dir, "status")) -> read_status(dir)
      File.exists?(Path.join(dir, "output")) -> {:ok, {:exited, nil}}
      true -> {:error, :not_found}
    end
  end

  defp read_status(dir) do
    case File.read(Path.join(dir, "status")) do
      {:ok, "timeout"} -> {:ok, :timeout}
      {:ok, code} -> {:ok, {:exited, String.to_integer(code)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_range(_path, _offset, 0), do: {:ok, ""}

  defp read_range(path, offset, bytes) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case :file.pread(file, offset, bytes) do
          {:ok, data} -> {:ok, data}
          :eof -> {:ok, ""}
          {:error, reason} -> {:error, reason}
        end
      after
        File.close(file)
      end
    end
  end

  defp process_path(%State{process_dir: root}, id), do: Path.join(root, Processes.dir_name(id))

  # mount/3 intentionally not implemented — host fs is the sandbox.

  # ============================================================================
  # Internals
  # ============================================================================

  defp resolve(path, cwd) do
    if Path.type(path) == :absolute, do: path, else: Path.expand(path, cwd)
  end

  defp resolve_optional(nil, cwd), do: cwd
  defp resolve_optional(path, cwd), do: resolve(path, cwd)

  defp build_env(overrides) do
    @safe_env_vars
    |> Enum.reduce(%{}, fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
    |> Map.merge(@base_env)
    |> Map.merge(normalize_env(overrides))
    |> Enum.to_list()
  end

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_env(env) when is_list(env) do
    Map.new(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_env(_), do: %{}

  defp capture_path do
    Path.join(System.tmp_dir!(), "condukt-command-#{System.unique_integer([:monotonic, :positive])}.log")
  end

  defp capture_output(path, fallback) do
    case File.read(path) do
      {:ok, output} -> output
      {:error, _reason} -> fallback
    end
  end

  defp format_error(error) do
    if is_exception(error), do: Exception.message(error), else: inspect(error)
  end

  defp count_occurrences(content, old_text) do
    content
    |> String.split(old_text)
    |> length()
    |> Kernel.-(1)
  end

  defp replace_first(content, old_text, new_text) do
    case :binary.match(content, old_text) do
      :nomatch ->
        {:ok, content}

      {index, len} ->
        new_content =
          binary_part(content, 0, index) <>
            new_text <>
            binary_part(content, index + len, byte_size(content) - index - len)

        {:ok, new_content}
    end
  end

  defp apply_limit(paths, nil), do: paths
  defp apply_limit(paths, limit) when is_integer(limit) and limit > 0, do: Enum.take(paths, limit)
  defp apply_limit(paths, _), do: paths

  defp compile_regex(pattern, case_sensitive?) do
    opts = if case_sensitive?, do: [], else: [:caseless]

    case Regex.compile(pattern, opts) do
      {:ok, regex} -> {:ok, regex}
      {:error, {reason, position}} -> {:error, {:invalid_regex, reason, position}}
    end
  end

  defp scan_file(path, regex, base) do
    case File.read(path) do
      {:ok, content} -> scan_content(content, regex, Path.relative_to(path, base))
      {:error, _} -> []
    end
  end

  defp scan_content(content, regex, rel_path) do
    content
    |> String.split("\n")
    |> Stream.with_index(1)
    |> Stream.flat_map(&match_line(&1, regex, rel_path))
  end

  defp match_line({line, line_number}, regex, rel_path) do
    if Regex.match?(regex, line) do
      [%{path: rel_path, line_number: line_number, line: line}]
    else
      []
    end
  end
end
