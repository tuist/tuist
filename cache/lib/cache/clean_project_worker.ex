defmodule Cache.CleanProjectWorker do
  @moduledoc """
  Oban worker that cleans all cache artifacts for a project from both disk and S3.
  """

  use Oban.Worker, queue: :clean, max_attempts: 3

  alias Cache.Config
  alias Cache.Disk
  alias Cache.DistributedKV.Cleanup, as: DistributedCleanup
  alias Cache.KeyValueEntries
  alias Cache.S3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}) do
    if Config.distributed_kv_enabled?() do
      perform_distributed_cleanup(account_handle, project_handle)
    else
      perform_local_cleanup(account_handle, project_handle)
    end

    :ok
  end

  defp perform_local_cleanup(account_handle, project_handle) do
    cutoff = DateTime.utc_now()
    invalidate_local_kv(account_handle, project_handle, cutoff)

    case Disk.delete_project(account_handle, project_handle) do
      :ok ->
        Logger.info("Cleaned disk cache for project #{account_handle}/#{project_handle}")

      {:error, reason} ->
        Logger.error("Failed to clean disk cache for project #{account_handle}/#{project_handle}: #{inspect(reason)}")
    end

    if Config.xcode_cache_bucket() do
      delete_s3_artifacts(account_handle, project_handle, :xcode_cache, "xcode cache")
    end

    delete_s3_artifacts(account_handle, project_handle, :cache, "cache")
  end

  defp perform_distributed_cleanup(account_handle, project_handle) do
    {:ok, cleanup_started_at} = DistributedCleanup.begin_project_cleanup(account_handle, project_handle)
    invalidate_local_kv(account_handle, project_handle, cleanup_started_at)
    delete_disk_with_cutoff(account_handle, project_handle, cleanup_started_at)

    if Config.xcode_cache_bucket() do
      delete_s3_artifacts_with_cutoff(account_handle, project_handle, :xcode_cache, "xcode cache", cleanup_started_at)
    end

    delete_s3_artifacts_with_cutoff(account_handle, project_handle, :cache, "cache", cleanup_started_at)

    tombstoned = DistributedCleanup.tombstone_project_entries(account_handle, project_handle, cleanup_started_at)

    Logger.info(
      "Distributed cleanup finished for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(cleanup_started_at)} (tombstoned=#{tombstoned})"
    )
  end

  defp invalidate_local_kv(account_handle, project_handle, cutoff) do
    {keys, _count} = KeyValueEntries.delete_project_entries_before(account_handle, project_handle, cutoff)
    Enum.each(keys, &Cachex.del(:cache_keyvalue_store, &1))
  end

  defp delete_disk_with_cutoff(account_handle, project_handle, cleanup_started_at) do
    {:ok, count} = Disk.delete_project_before(account_handle, project_handle, cleanup_started_at)
    Logger.info("Cleaned #{count} disk artifacts for project #{account_handle}/#{project_handle} with cutoff")
  end

  defp delete_s3_artifacts(account_handle, project_handle, type, label) do
    prefix = "#{account_handle}/#{project_handle}/"

    case S3.delete_all_with_prefix(prefix, type: type) do
      {:ok, count} ->
        Logger.info("Cleaned #{count} S3 #{label} objects with prefix #{prefix}")

      {:error, reason} ->
        Logger.error("Failed to clean S3 #{label} objects with prefix #{prefix}: #{inspect(reason)}")
    end
  end

  defp delete_s3_artifacts_with_cutoff(account_handle, project_handle, type, label, cleanup_started_at) do
    prefix = "#{account_handle}/#{project_handle}/"

    case S3.delete_objects_with_prefix_before(prefix, cleanup_started_at, type: type) do
      {:ok, count} ->
        Logger.info("Cleaned #{count} S3 #{label} objects with prefix #{prefix} using cutoff-aware deletion")

      {:error, reason} ->
        Logger.error("Failed cutoff-aware S3 #{label} cleanup for prefix #{prefix}: #{inspect(reason)}")
    end
  end
end
