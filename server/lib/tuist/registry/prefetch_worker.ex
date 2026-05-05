defmodule Tuist.Registry.PrefetchWorker do
  @moduledoc """
  Downloads a registry artifact from S3 onto the local PVC of a serving pod.

  Enqueued by the registry controller on a disk miss so subsequent requests for
  the same artifact can be served via nginx `x-accel-redirect` from local disk.
  Runs only on registry-serving pods (`TUIST_MODE=registry_serving`) where the
  PVC is mounted; the population pod ignores this queue.
  """

  use Oban.Worker,
    queue: :registry_prefetch,
    max_attempts: 3,
    unique: [
      keys: [:key],
      states: [:available, :scheduled, :executing, :retryable],
      period: :infinity
    ]

  alias Tuist.Registry.Disk
  alias Tuist.Registry.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) when is_binary(key) do
    case parse_key(key) do
      {:ok, scope, name, version, filename} ->
        prefetch(scope, name, version, filename)

      :error ->
        Logger.warning("Registry prefetch skipped for unrecognised key: #{key}")
        :ok
    end
  end

  defp prefetch(scope, name, version, filename) do
    if Disk.exists?(scope, name, version, filename) do
      :ok
    else
      {:ok, tmp_path} = Briefly.create()

      key = Disk.key(scope, name, version, filename)

      case Storage.download_to_file(key, tmp_path) do
        {:ok, :done} ->
          Disk.put(scope, name, version, filename, {:file, tmp_path})

        {:ok, _} ->
          Disk.put(scope, name, version, filename, {:file, tmp_path})

        {:error, reason} ->
          File.rm(tmp_path)
          Logger.warning("Registry prefetch failed for #{key}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Enqueues a prefetch for a known S3 key.
  """
  def enqueue(key) when is_binary(key) do
    %{key: key}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp parse_key(key) do
    case Regex.run(~r{^registry/swift/([^/]+)/([^/]+)/([^/]+)/([^/]+)$}, key) do
      [_, scope, name, version, filename] -> {:ok, scope, name, version, filename}
      _ -> :error
    end
  end
end
