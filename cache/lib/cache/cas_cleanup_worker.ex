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

  @min_hash_length 4

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"account_handle" => account_handle, "project_handle" => project_handle, "cas_hashes" => cas_hashes}
      }) do
    valid_hashes = filter_valid_hashes(cas_hashes)
    still_referenced = KeyValueEntries.referenced_hashes(account_handle, project_handle, valid_hashes)

    case valid_hashes -- still_referenced do
      [] ->
        :ok

      unreferenced ->
        keys = Enum.map(unreferenced, &CAS.Disk.key(account_handle, project_handle, &1))
        delete_from_disk(keys)

        case delete_from_s3(keys) do
          [] -> :ok
          s3_deleted_keys -> delete_from_metadata(s3_deleted_keys)
        end

        :ok
    end
  end

  defp filter_valid_hashes(hashes) do
    {valid, invalid} = Enum.split_with(hashes, &(String.length(&1) >= @min_hash_length))

    Enum.each(invalid, fn hash ->
      Logger.warning("Skipping CAS hash shorter than #{@min_hash_length} characters: #{hash}")
    end)

    valid
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
