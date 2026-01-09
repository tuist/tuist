defmodule Cache.Registry.SyncWorker do
  @moduledoc """
  Oban worker that periodically syncs Swift package registry metadata from the server.

  Runs every 60 minutes and uses leader election to ensure only one cache node
  performs the sync at a time. This respects GitHub rate limits by preventing
  multiple nodes from fetching package data simultaneously.

  ## Algorithm

  1. Attempt to acquire leader lock via `LeaderElection.try_acquire_lock/0`
  2. If not leader, skip sync and return `:ok`
  3. If leader:
     a. Fetch package list from server API
     b. For each package, enqueue a `ReleaseWorker` job
     c. Release the leader lock
  """

  use Oban.Worker, queue: :registry_sync

  alias Cache.Registry.LeaderElection
  alias Cache.Registry.ReleaseWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case LeaderElection.try_acquire_lock() do
      {:ok, :acquired} ->
        try do
          sync_packages()
        after
          LeaderElection.release_lock()
        end

      {:error, :already_locked} ->
        Logger.debug("Registry sync skipped: another node is the leader")
        :ok
    end
  end

  defp sync_packages do
    case fetch_packages_from_server() do
      {:ok, packages} ->
        Logger.info("Fetched #{length(packages)} packages from server, enqueueing release workers")
        enqueue_release_workers(packages)
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch packages from server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_packages_from_server do
    server_url = server_url()
    url = "#{server_url}/api/registry/swift/packages"

    case Req.get(url, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        packages = Map.get(body, "packages", Map.get(body, "data", []))
        {:ok, packages}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enqueue_release_workers(packages) do
    Enum.each(packages, fn package ->
      scope = package["scope"] || extract_scope(package)
      name = package["name"] || extract_name(package)

      if scope && name do
        %{scope: scope, name: name}
        |> ReleaseWorker.new()
        |> Oban.insert()
      else
        Logger.warning("Skipping package with missing scope or name: #{inspect(package)}")
      end
    end)
  end

  defp extract_scope(%{"repository_full_handle" => handle}) when is_binary(handle) do
    case String.split(handle, "/", parts: 2) do
      [scope, _name] -> scope
      _ -> nil
    end
  end

  defp extract_scope(_), do: nil

  defp extract_name(%{"repository_full_handle" => handle}) when is_binary(handle) do
    case String.split(handle, "/", parts: 2) do
      [_scope, name] -> name
      _ -> nil
    end
  end

  defp extract_name(_), do: nil

  defp server_url do
    Application.get_env(:cache, :server_url, "http://localhost:4000")
  end
end
