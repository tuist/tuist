defmodule Condukt.Sandbox.Local do
  @moduledoc """
  Sandbox that operates against the host filesystem and host shell.

  This is the default sandbox. It carries a base `:cwd` (resolved at
  `init/1`) that all relative paths and command executions use as their root.

  `mount/3` is unsupported (the host filesystem is the sandbox).

  ## Initializing

      {:ok, sandbox} = Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: "/tmp")
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Local.State

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

    {:ok, %State{cwd: cwd}}
  end

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
