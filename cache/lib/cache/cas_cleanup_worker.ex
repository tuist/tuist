defmodule Cache.CASCleanupWorker do
  @moduledoc """
  Oban worker that deletes CAS artifacts from disk, S3, and metadata.

  Best-effort: failures are logged but do not cause retries.
  Only deletes artifacts that are no longer referenced by any key-value entry.
  """

  use Oban.Worker, queue: :clean, max_attempts: 1

  alias Cache.CacheArtifacts
  alias Cache.CAS.Disk, as: CASDisk
  alias Cache.Config
  alias Cache.Disk
  alias Cache.KeyValueEntries

  require Logger

  @min_hash_length 4

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"account_handle" => account_handle, "project_handle" => project_handle, "cas_hashes" => cas_hashes}
      }) do
    valid_hashes = filter_valid_hashes(cas_hashes)
    still_referenced = KeyValueEntries.referenced_hashes(account_handle, project_handle, valid_hashes)
    unreferenced = valid_hashes -- still_referenced

    if unreferenced == [] do
      :ok
    else
      keys = build_cas_keys(account_handle, project_handle, unreferenced)
      disk_cleaned_keys = delete_from_disk(keys)

      if disk_cleaned_keys != [] do
        delete_from_s3(disk_cleaned_keys)
        delete_from_metadata(disk_cleaned_keys)
      end

      :ok
    end
  end

  defp filter_valid_hashes(hashes) do
    Enum.filter(hashes, fn hash ->
      if String.length(hash) < @min_hash_length do
        Logger.warning("Skipping CAS hash shorter than 4 characters: #{hash}")
        false
      else
        true
      end
    end)
  end

  defp build_cas_keys(account_handle, project_handle, hashes) do
    Enum.map(hashes, fn hash ->
      CASDisk.key(account_handle, project_handle, hash)
    end)
  end

  defp delete_from_disk(keys) do
    Enum.filter(keys, fn key ->
      path = Disk.artifact_path(key)

      case File.rm(path) do
        :ok ->
          true

        {:error, :enoent} ->
          true

        {:error, reason} ->
          Logger.error("Failed to delete CAS artifact from disk #{path}: #{inspect(reason)}")
          false
      end
    end)
  end

  defp delete_from_s3(keys) do
    bucket = Config.cache_bucket()

    case bucket |> ExAws.S3.delete_multiple_objects(keys) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Deleted #{length(keys)} CAS artifacts from S3")

      {:error, reason} ->
        Logger.error("Failed to delete S3 objects: #{inspect(reason)}")
    end
  end

  defp delete_from_metadata(keys) do
    CacheArtifacts.delete_by_keys(keys)
  end
end
