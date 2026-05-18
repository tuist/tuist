defmodule Cache.SocketLinker do
  @moduledoc false

  require Logger

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [fn -> promote_socket_link() end]},
      restart: :transient,
      shutdown: 5_000
    }
  end

  defp promote_socket_link do
    with {:ok, target} <- get_socket_path(),
         {:ok, link} <- socket_env("PHX_SOCKET_LINK") do
      File.mkdir_p!(Path.dirname(link))
      wait_for_up(target)
      publish_link(target, link)
    else
      _ -> :ok
    end
  end

  defp get_socket_path do
    case Application.get_env(:cache, :socket_path) do
      nil -> :error
      path -> {:ok, path}
    end
  end

  defp publish_link(target, link) do
    tmp_link = "#{link}.tmp"

    _ = File.rm(tmp_link)

    case File.ln_s(target, tmp_link) do
      :ok ->
        :ok = File.chmod(target, 0o777)
        :ok = File.rename(tmp_link, link)
        Logger.info("Socket link promoted: #{link} -> #{target}")
        cleanup_stale_sockets(target)

      {:error, reason} ->
        Logger.error("Failed to create socket symlink #{tmp_link}: #{inspect(reason)}")
    end
  end

  defp cleanup_stale_sockets(target) do
    dir = Path.dirname(target)
    pattern = Path.join(dir, "cache-*.sock")

    pattern
    |> Path.wildcard()
    |> Enum.each(fn socket ->
      if socket != target do
        _ = File.rm(socket)
      end
    end)
  end

  defp socket_env(var) do
    case System.get_env(var) do
      value when value in [nil, ""] ->
        :error

      value ->
        {:ok, value}
    end
  end

  defp wait_for_up(target, attempt \\ 0) do
    case System.cmd(
           "curl",
           ["--silent", "--show-error", "--fail", "--max-time", "35", "--unix-socket", target, "http://localhost/up"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, _status} ->
        maybe_log_wait_for_up(target, attempt, output)
        Process.sleep(100)
        wait_for_up(target, attempt + 1)
    end
  end

  defp maybe_log_wait_for_up(target, attempt, output) do
    if rem(attempt, 50) == 0 do
      Logger.info("Waiting for /up on socket #{target}: #{String.trim(output)}")
    end
  end
end
