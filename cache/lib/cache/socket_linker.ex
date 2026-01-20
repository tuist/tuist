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
    with {:ok, target} <- socket_env("PHX_SOCKET_PATH"),
         {:ok, link} <- socket_env("PHX_SOCKET_LINK") do
      File.mkdir_p!(Path.dirname(link))
      wait_for_socket(target)
      publish_link(target, link)
    else
      _ -> :ok
    end
  end

  defp wait_for_socket(target, attempt \\ 0) do
    case File.stat(target) do
      {:ok, _stat} ->
        :ok

      {:error, :enoent} ->
        maybe_log_wait(target, attempt)
        Process.sleep(100)
        wait_for_socket(target, attempt + 1)

      {:error, reason} ->
        Logger.warning("Waiting for socket #{target} failed with #{inspect(reason)}; retrying")
        Process.sleep(100)
        wait_for_socket(target, attempt + 1)
    end
  end

  defp maybe_log_wait(target, attempt) do
    if rem(attempt, 50) == 0 do
      Logger.info("Waiting for socket #{target} to become available")
    end
  end

  defp publish_link(target, link) do
    tmp_link = "#{link}.tmp"

    _ = File.rm(tmp_link)

    case File.ln_s(target, tmp_link) do
      :ok ->
        _ = File.rm(link)
        :ok = File.rename(tmp_link, link)
        :ok = File.chmod(link, 0o777)
        Logger.info("Socket link promoted: #{link} -> #{target}")

      {:error, reason} ->
        Logger.error("Failed to create socket symlink #{tmp_link}: #{inspect(reason)}")
    end
  end

  defp socket_env(var) do
    case System.get_env(var) do
      value when value in [nil, ""] ->
        :error

      value ->
        {:ok, value}
    end
  end
end
