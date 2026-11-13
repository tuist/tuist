defmodule Condukt.Sandbox.Virtual do
  @moduledoc """
  Sandbox that runs against an in-memory virtual filesystem and a
  Rust-implemented bash interpreter via the bashkit NIF.

  No host process spawning by default. Host directories can be mounted into
  the virtual filesystem at construction time via `:mounts`, or at runtime via
  `Condukt.Sandbox.Virtual.Tools.Mount`.

  ## Initializing

      {:ok, sandbox} = Condukt.Sandbox.new(Condukt.Sandbox.Virtual)

      # Mount the host project at /workspace, read-only:
      {:ok, sandbox} =
        Condukt.Sandbox.new(Condukt.Sandbox.Virtual,
          mounts: [{File.cwd!(), "/workspace", :readonly}]
        )

  ## Notes

  Each `exec/3` call is stateless: shell variables, `cd`, and `export` do not
  persist across calls. This matches `Sandbox.Local`'s contract and lets the
  Bash tool behave identically in both sandboxes. For a stateful interactive
  shell, use `Condukt.Sandbox.Virtual.Tools.Shell` (planned).
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Bashkit.NIF
  alias Condukt.Sandbox
  alias Condukt.Sandbox.Virtual.State

  # ============================================================================
  # Sandbox callbacks
  # ============================================================================

  # Bashkit's interpreter starts with this cwd. Used to reset between
  # exec/3 calls so the sandbox stays stateless. Override with the
  # `:cwd` init option if you mounted a workspace elsewhere.
  @default_base_cwd "/home/user"

  @impl Sandbox
  def init(opts) do
    with {:ok, mounts} <- normalize_mounts(Keyword.get(opts, :mounts, [])),
         {:ok, session} <- start_nif_session(mounts) do
      base_cwd = Keyword.get(opts, :cwd, @default_base_cwd)
      {:ok, %State{session: session, base_cwd: base_cwd}}
    end
  end

  defp start_nif_session(mounts) do
    {:ok, NIF.new_session(mounts)}
  catch
    kind, reason -> {:error, format_caught(kind, reason)}
  end

  defp format_caught(_kind, reason) do
    if is_exception(reason), do: Exception.message(reason), else: inspect(reason)
  end

  @impl Sandbox
  def shutdown(%State{session: session}) do
    _ = NIF.shutdown(session)
    :ok
  end

  @impl Sandbox
  def cwd(%State{base_cwd: base_cwd}), do: base_cwd

  @impl Sandbox
  def read_file(%State{session: session}, path) do
    NIF.read_file(session, path)
  end

  @impl Sandbox
  def write_file(%State{session: session}, path, content) do
    with {:ok, :ok} <- NIF.write_file(session, path, content), do: :ok
  end

  @impl Sandbox
  def edit_file(%State{session: session}, path, old_text, new_text) do
    NIF.edit_file(session, path, old_text, new_text)
  end

  @impl Sandbox
  def exec(%State{session: session, base_cwd: base_cwd}, command, opts) do
    timeout = Keyword.get(opts, :timeout)
    env = Keyword.get(opts, :env, [])

    # Stateless exec: each call resets cwd to the sandbox's base, then
    # optionally `cd`s into the per-call :cwd. This matches Sandbox.Local
    # where each call starts fresh.
    target_cwd = Keyword.get(opts, :cwd) || base_cwd

    script =
      case target_cwd do
        nil -> command
        cwd -> "cd #{shell_quote(cwd)} && #{command}"
      end
      |> prepend_env_exports(env)

    NIF.exec(session, script, timeout)
  end

  @impl Sandbox
  def glob(%State{session: session}, pattern, opts) do
    NIF.glob(session, pattern, opts[:cwd])
  end

  @impl Sandbox
  def grep(%State{session: session}, pattern, opts) do
    NIF.grep(
      session,
      pattern,
      opts[:path],
      Keyword.get(opts, :case_sensitive, true),
      opts[:glob]
    )
  end

  @impl Sandbox
  def mount(%State{session: session}, host_path, vfs_path) do
    with {:ok, :ok} <- NIF.mount(session, host_path, vfs_path, :readwrite), do: :ok
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp normalize_mounts(mounts) when is_list(mounts) do
    Enum.reduce_while(mounts, {:ok, []}, fn entry, {:ok, acc} ->
      case normalize_mount(entry) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp normalize_mounts(_), do: {:error, ":mounts must be a list of {host, vfs[, mode]}"}

  defp normalize_mount({host, vfs}), do: {:ok, {to_string(host), to_string(vfs), :readwrite}}

  defp normalize_mount({host, vfs, mode}) when mode in [:readonly, :readwrite],
    do: {:ok, {to_string(host), to_string(vfs), mode}}

  defp normalize_mount(other), do: {:error, "invalid mount spec: #{inspect(other)}"}

  defp shell_quote(s) do
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end

  defp prepend_env_exports(script, []), do: script

  defp prepend_env_exports(script, env) do
    case normalize_env(env) do
      [] ->
        script

      normalized ->
        exports = Enum.map_join(normalized, "\n", fn {key, value} -> "export #{key}=#{shell_quote(value)}" end)
        exports <> "\n" <> script
    end
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
end
