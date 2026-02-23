defmodule Cache.CASCleanupWorker do
  @moduledoc """
  Oban worker that deletes CAS artifacts from disk and metadata.
  Only deletes artifacts that are no longer referenced by any key-value entry.
  Artifacts flow through disk → metadata deletion. Each stage only
  receives keys that the previous stage successfully cleaned up, so a failure
  at any point leaves metadata intact for retries.
  """
  use Oban.Worker,
    queue: :clean,
    max_attempts: 3,
    unique: [keys: [:account_handle, :project_handle], period: 300]

  alias Cache.CacheArtifacts
  alias Cache.CAS
  alias Cache.Disk
  alias Cache.KeyValueEntries

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"account_handle" => account_handle, "project_handle" => project_handle, "cas_hashes" => cas_hashes}
      }) do
    case KeyValueEntries.unreferenced_hashes(cas_hashes, account_handle, project_handle) do
      [] ->
        :ok

      unreferenced ->
        unreferenced
        |> Enum.map(&CAS.Disk.key(account_handle, project_handle, &1))
        |> delete_from_disk()
        |> delete_from_metadata()

        :ok
    end
  end

  defp delete_from_disk(keys) do
    Enum.filter(keys, fn key ->
      case Disk.delete_artifact(key) do
        :ok ->
          true

        {:error, :enoent} ->
          true

        {:error, reason} ->
          Logger.error("Failed to delete CAS artifact from disk #{key}: #{inspect(reason)}")
          false
      end
    end)
  end

  defp delete_from_metadata(keys) do
    CacheArtifacts.delete_by_keys(keys)
  end
end
