defmodule Cache.CASCleanupWorker do
  @moduledoc """
  Oban worker that deletes CAS artifacts from disk, S3, and metadata.

  Only deletes artifacts that are no longer referenced by any key-value entry.
  Disk cleanup is best-effort. Metadata is only removed after confirmed S3 deletion.
  """

  use Oban.Worker,
    queue: :clean,
    max_attempts: 3,
    unique: [keys: [:account_handle, :project_handle], period: 300]

  alias Cache.CacheArtifacts
  alias Cache.CAS
  alias Cache.Config
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

        # Disk is best-effort — the eviction worker will reclaim space eventually.
        # Metadata is only removed for keys confirmed deleted from S3,
        # since S3 is the authoritative copy and orphaned metadata is harmless.
        delete_from_disk(keys)
        keys |> delete_from_s3() |> delete_from_metadata()
        :ok
    end
  end

  defp delete_from_disk(keys) do
    Enum.each(keys, fn key ->
      case Disk.delete_artifact(key) do
        :ok ->
          :ok

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to delete CAS artifact from disk #{key}: #{inspect(reason)}")
      end
    end)
  end

  defp delete_from_s3(keys) do
    bucket = Config.cache_bucket()

    keys
    |> Enum.chunk_every(1000)
    |> Enum.flat_map(fn chunk ->
      case bucket |> ExAws.S3.delete_multiple_objects(chunk) |> ExAws.request() do
        {:ok, _} ->
          Logger.info("Deleted #{length(chunk)} CAS artifacts from S3")
          chunk

        {:error, reason} ->
          Logger.error("Failed to delete S3 objects: #{inspect(reason)}")
          []
      end
    end)
  end

  defp delete_from_metadata(keys) do
    CacheArtifacts.delete_by_keys(keys)
  end
end
