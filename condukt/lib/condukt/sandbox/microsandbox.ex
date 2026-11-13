defmodule Condukt.Sandbox.Microsandbox do
  @moduledoc """
  Sandbox backend powered by the `microsandbox` microVM runtime through a Rust NIF.

  By default this sandbox boots an OCI image, bind-mounts the current host
  workspace at `/workspace`, and runs commands there. That makes it suitable
  for the built-in coding tools while keeping command execution inside the
  guest VM instead of the host process.

  ## Initializing

      {:ok, sandbox} =
        Condukt.Sandbox.new(Condukt.Sandbox.Microsandbox,
          image: "ubuntu:24.04"
        )

      {:ok, sandbox} =
        Condukt.Sandbox.new(Condukt.Sandbox.Microsandbox,
          image: "ghcr.io/myorg/elixir-dev:latest",
          cwd: "/repo",
          workspace_host: File.cwd!(),
          mounts: [{"/tmp/cache", "/cache", :readwrite}]
        )

  ## Options

  * `:image` - OCI image to boot. Defaults to `"ubuntu:24.04"`.
  * `:cwd` - Guest working directory. Defaults to `/workspace`.
  * `:workspace_host` - Host directory to bind-mount at `:cwd`. Defaults to
    `File.cwd!/0`.
  * `:mount_workspace` - Whether to add the default workspace bind mount.
    Defaults to `true`.
  * `:mounts` - Additional construction-time bind mounts as
    `{host, guest}` or `{host, guest, :readonly | :readwrite}` tuples.
  * `:shell` - Shell used for `exec/3`. Defaults to `/bin/bash`.
  * `:cpus` - Virtual CPU count. Defaults to `2`.
  * `:memory` - Guest memory in MiB. Defaults to `1024`.
  * `:env` - Sandbox-wide environment variables.
  * `:replace_existing` - Replace a leftover sandbox with the same session id.
    Defaults to `true`.

  ## Current limits

  * Runtime `mount/3` is not supported because `microsandbox` only exposes
    volume configuration at sandbox creation time.
  * `glob/3` and `grep/3` operate on host-backed bind mounts. Paths outside a
    bind mount return `{:error, :not_supported}` for those operations.
  * `Condukt.Sandbox.NetworkPolicy` remains Kubernetes-specific. This backend
    does not translate it yet.
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Microsandbox.NIF
  alias Condukt.Sandbox
  alias Condukt.Sandbox.Microsandbox.State

  @default_image "ubuntu:24.04"
  @default_cwd "/workspace"
  @default_shell "/bin/bash"
  @default_cpus 2
  @default_memory_mib 1024

  @impl Sandbox
  def init(opts) do
    mount_workspace? = Keyword.get(opts, :mount_workspace, true)
    base_cwd = normalize_base_cwd(opts[:cwd], mount_workspace?)
    workspace_host = Path.expand(Keyword.get(opts, :workspace_host, File.cwd!()))
    nif_module = Keyword.get(opts, :nif_module, NIF)

    with {:ok, mounts} <- normalize_mounts(Keyword.get(opts, :mounts, [])),
         {:ok, mounts} <- maybe_add_workspace_mount(mounts, workspace_host, base_cwd, mount_workspace?),
         {:ok, session} <- start_session(opts, base_cwd, mounts, nif_module) do
      {:ok,
       %State{
         session: session,
         base_cwd: base_cwd,
         shell: Keyword.get(opts, :shell, @default_shell),
         nif_module: nif_module,
         mounts: mounts
       }}
    end
  end

  @impl Sandbox
  def shutdown(%State{session: session, nif_module: nif_module}) do
    _ = nif_module.shutdown(session)
    :ok
  end

  @impl Sandbox
  def cwd(%State{base_cwd: base_cwd}), do: base_cwd

  @impl Sandbox
  def read_file(%State{session: session, base_cwd: base_cwd, nif_module: nif_module}, path) do
    session
    |> nif_module.read_file(resolve_guest_path(path, base_cwd))
    |> normalize_result()
  end

  @impl Sandbox
  def write_file(%State{session: session, base_cwd: base_cwd, nif_module: nif_module}, path, content) do
    session
    |> nif_module.write_file(resolve_guest_path(path, base_cwd), content)
    |> normalize_result()
  end

  @impl Sandbox
  def edit_file(%State{} = state, path, old_text, new_text) do
    guest_path = resolve_guest_path(path, state.base_cwd)

    with {:ok, content} <- read_file(state, guest_path) do
      apply_edit(state, guest_path, content, old_text, new_text)
    end
  end

  defp apply_edit(state, guest_path, content, old_text, new_text) do
    case count_occurrences(content, old_text) do
      0 ->
        {:ok, %{occurrences: 0, content: content}}

      count when count > 1 ->
        {:ok, %{occurrences: count, content: content}}

      1 ->
        new_content = String.replace(content, old_text, new_text, global: false)

        with :ok <- write_file(state, guest_path, new_content) do
          {:ok, %{occurrences: 1, content: new_content}}
        end
    end
  end

  @impl Sandbox
  def exec(%State{session: session, base_cwd: base_cwd, shell: shell, nif_module: nif_module}, command, opts) do
    run_cwd = opts |> Keyword.get(:cwd) |> resolve_optional_guest(base_cwd)
    env = normalize_env(Keyword.get(opts, :env, []))
    timeout = Keyword.get(opts, :timeout)

    session
    |> nif_module.exec(shell, command, run_cwd, env, timeout)
    |> normalize_exec_result()
  end

  @impl Sandbox
  def glob(%State{} = state, pattern, opts) do
    guest_base = opts |> Keyword.get(:cwd) |> resolve_optional_guest(state.base_cwd)
    full_pattern = resolve_guest_pattern(pattern, guest_base)

    with {:ok, _host_base, mount} <- host_path_for_guest(state, guest_base),
         {:ok, host_pattern} <- host_pattern_for_guest(state, full_pattern) do
      paths =
        host_pattern
        |> Path.wildcard(match_dot: true)
        |> Enum.sort()
        |> Enum.map(&host_to_guest_path(mount, &1))
        |> Enum.map(&Path.relative_to(&1, guest_base))
        |> apply_limit(opts[:limit])

      {:ok, paths}
    end
  end

  @impl Sandbox
  def grep(%State{} = state, pattern, opts) do
    guest_base = opts |> Keyword.get(:path) |> resolve_optional_guest(state.base_cwd)
    case_sensitive? = Keyword.get(opts, :case_sensitive, true)
    file_glob = Keyword.get(opts, :glob, "**/*")
    limit = Keyword.get(opts, :limit, 1_000)

    with {:ok, regex} <- compile_regex(pattern, case_sensitive?),
         {:ok, host_base, mount} <- host_path_for_guest(state, guest_base) do
      matches =
        host_base
        |> Path.join(file_glob)
        |> Path.wildcard(match_dot: false)
        |> Enum.filter(&File.regular?/1)
        |> Stream.flat_map(&scan_file(&1, regex, host_base, guest_base, mount))
        |> Enum.take(limit)

      {:ok, matches}
    end
  end

  defp start_session(opts, base_cwd, mounts, nif_module) do
    config = %{
      name: sandbox_name(Keyword.get(opts, :id)),
      image: Keyword.get(opts, :image, @default_image),
      cpus: Keyword.get(opts, :cpus, @default_cpus),
      memory_mib: Keyword.get(opts, :memory, @default_memory_mib),
      cwd: base_cwd,
      shell: Keyword.get(opts, :shell, @default_shell),
      env: normalize_env(Keyword.get(opts, :env, [])),
      mounts: Enum.map(mounts, &mount_to_map/1),
      replace_existing: Keyword.get(opts, :replace_existing, true)
    }

    case nif_module.new_session(config) do
      {:ok, session} -> {:ok, session}
      {:error, _} = err -> err
    end
  end

  defp sandbox_name(nil), do: "condukt-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  defp sandbox_name(id), do: "condukt-" <> to_string(id)

  defp mount_to_map({host_path, guest_path, mode}) do
    %{
      host_path: host_path,
      guest_path: guest_path,
      mode: mode
    }
  end

  defp normalize_base_cwd(nil, true), do: @default_cwd
  defp normalize_base_cwd(nil, false), do: "/"
  defp normalize_base_cwd(path, _mount_workspace?), do: resolve_guest_path(path, "/")

  defp normalize_mounts(mounts) when is_list(mounts) do
    Enum.reduce_while(mounts, {:ok, []}, fn entry, {:ok, acc} ->
      case normalize_mount(entry) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, sort_mounts(Enum.reverse(list))}
      err -> err
    end
  end

  defp normalize_mounts(_), do: {:error, ":mounts must be a list of {host, guest[, mode]} tuples"}

  defp normalize_mount({host, guest}), do: normalize_mount({host, guest, :readwrite})

  defp normalize_mount({host, guest, mode}) when mode in [:readonly, :readwrite] do
    {:ok, {Path.expand(to_string(host)), resolve_guest_path(to_string(guest), "/"), mode}}
  end

  defp normalize_mount(other), do: {:error, "invalid mount spec: #{inspect(other)}"}

  defp maybe_add_workspace_mount(mounts, _workspace_host, _base_cwd, false), do: {:ok, mounts}

  defp maybe_add_workspace_mount(mounts, workspace_host, base_cwd, true) do
    if Enum.any?(mounts, fn {_host, guest, _mode} -> path_within?(base_cwd, guest) end) do
      {:ok, mounts}
    else
      {:ok, sort_mounts([{workspace_host, base_cwd, :readwrite} | mounts])}
    end
  end

  defp sort_mounts(mounts) do
    Enum.sort_by(mounts, fn {_host, guest, _mode} -> -String.length(guest) end)
  end

  defp normalize_result({:ok, :ok}), do: :ok
  defp normalize_result({:ok, value}), do: {:ok, value}
  defp normalize_result(:ok), do: :ok
  defp normalize_result({:error, reason}), do: {:error, normalize_reason(reason)}

  defp normalize_exec_result({:ok, value}), do: {:ok, value}
  defp normalize_exec_result({:error, "timeout"}), do: {:error, :timeout}
  defp normalize_exec_result({:error, reason}), do: {:error, normalize_reason(reason)}

  defp normalize_reason(:unsupported_target), do: :unsupported_target
  defp normalize_reason("enoent"), do: :enoent
  defp normalize_reason("eisdir"), do: :eisdir
  defp normalize_reason("eexist"), do: :eexist
  defp normalize_reason("eacces"), do: :eacces
  defp normalize_reason(reason), do: reason

  defp resolve_guest_pattern(pattern, guest_base) do
    if Path.type(pattern) == :absolute do
      pattern
    else
      Path.join(guest_base, pattern)
    end
  end

  defp resolve_guest_path(path, guest_base) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, guest_base)
    end
  end

  defp resolve_optional_guest(nil, guest_base), do: guest_base
  defp resolve_optional_guest(path, guest_base), do: resolve_guest_path(path, guest_base)

  defp host_path_for_guest(%State{mounts: mounts}, guest_path) do
    case Enum.find(mounts, fn {_host, guest, _mode} -> path_within?(guest_path, guest) end) do
      {host, guest, _mode} = mount ->
        suffix =
          guest_path
          |> String.trim_leading(guest)
          |> String.trim_leading("/")

        host_path =
          case suffix do
            "" -> host
            _ -> Path.join(host, suffix)
          end

        {:ok, host_path, mount}

      nil ->
        {:error, :not_supported}
    end
  end

  defp host_pattern_for_guest(%State{mounts: mounts}, guest_pattern) do
    case Enum.find(mounts, fn {_host, guest, _mode} -> path_within?(guest_pattern, guest) end) do
      {host, guest, _mode} ->
        suffix =
          guest_pattern
          |> String.trim_leading(guest)
          |> String.trim_leading("/")

        {:ok, if(suffix == "", do: host, else: Path.join(host, suffix))}

      nil ->
        {:error, :not_supported}
    end
  end

  defp host_to_guest_path({host_root, guest, _mode}, host_path) do
    suffix =
      host_path
      |> Path.relative_to(host_root)
      |> case do
        "." -> ""
        relative -> relative
      end

    case suffix do
      "" -> guest
      _ -> Path.join(guest, suffix)
    end
  end

  defp path_within?(path, mount_path) do
    path == mount_path or String.starts_with?(path, mount_path <> "/")
  end

  defp normalize_env(env) when is_map(env) do
    env
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Enum.filter(&valid_env?/1)
  end

  defp normalize_env(env) when is_list(env) do
    env
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Enum.filter(&valid_env?/1)
  end

  defp normalize_env(_), do: []

  defp valid_env?({key, _value}), do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, key)

  defp count_occurrences(content, old_text) do
    content
    |> String.split(old_text)
    |> length()
    |> Kernel.-(1)
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

  defp scan_file(path, regex, host_base, guest_base, mount) do
    case File.read(path) do
      {:ok, content} ->
        rel_host_path = Path.relative_to(path, host_base)
        guest_path = host_to_guest_path(mount, Path.join(elem(mount, 0), rel_host_path))
        rel_guest_path = Path.relative_to(guest_path, guest_base)
        scan_content(content, regex, rel_guest_path)

      {:error, _} ->
        []
    end
  end

  defp scan_content(content, regex, rel_path) do
    content
    |> String.split("\n")
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _line_number} -> Regex.match?(regex, line) end)
    |> Enum.map(fn {line, line_number} ->
      %{path: rel_path, line_number: line_number, line: line}
    end)
  end
end
