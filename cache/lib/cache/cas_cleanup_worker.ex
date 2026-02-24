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
    unique: [keys: [:account_handle, :project_handle, :cas_hashes], period: 300]

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
        keys = Enum.map(unreferenced, &CAS.Disk.key(account_handle, project_handle, &1))

        with {:ok, deleted_keys} <- delete_from_disk(keys) do
          delete_from_metadata(deleted_keys)
          :ok
        end
    end
  end

  defp delete_from_disk(keys) do
    {deleted_keys, failed_count} =
      Enum.reduce(keys, {[], 0}, fn key, {deleted_acc, failed_acc} ->
        case Disk.delete_artifact(key) do
          :ok ->
            {[key | deleted_acc], failed_acc}

          {:error, :enoent} ->
            {[key | deleted_acc], failed_acc}

          {:error, reason} ->
            Logger.error("Failed to delete CAS artifact from disk #{key}: #{inspect(reason)}")
            {deleted_acc, failed_acc + 1}
        end
      end)

    if failed_count == 0 do
      {:ok, Enum.reverse(deleted_keys)}
    else
      {:error, {:disk_delete_failed, failed_count}}
    end
  end

  defp delete_from_metadata(keys) do
    CacheArtifacts.delete_by_keys(keys)
  end
end
