defmodule CacheWeb.UpController do
  use CacheWeb, :controller

  alias Cache.Config

  require Logger

  def index(conn, _params) do
    case failing_check() do
      nil ->
        send_resp(conn, :ok, "UP! Version: " <> version())

      {repo, reason} ->
        Logger.warning("/up repo check failed for #{inspect(repo)}: #{reason}")
        send_resp(conn, :service_unavailable, "")
    end
  end

  defp version do
    System.get_env("KAMAL_VERSION") || System.get_env("RELEASE_VSN") || "unknown"
  end

  defp failing_check do
    Enum.find_value(healthcheck_repos(), fn repo ->
      case query_repo(repo) do
        :ok -> nil
        {:error, reason} -> {repo, reason}
      end
    end)
  end

  defp healthcheck_repos do
    [Cache.Repo, Cache.KeyValueRepo] ++
      if(Config.distributed_kv_enabled?(), do: [Cache.DistributedKV.Repo], else: [])
  end

  defp query_repo(repo) do
    case repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, Exception.format_exit(reason)}
  end
end
