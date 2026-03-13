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
      :ok
    end
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
    with {:ok, cleanup_started_at} <- DistributedCleanup.begin_project_cleanup(account_handle, project_handle) do
      safe_cleanup_cutoff = DistributedCleanup.safe_cleanup_cutoff(cleanup_started_at)

      renew_lease = fn ->
        DistributedCleanup.renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at)
      end

      with :ok <- renew_lease.(),
           :ok <- invalidate_local_kv(account_handle, project_handle, safe_cleanup_cutoff),
           :ok <- renew_lease.(),
           :ok <- delete_disk_with_cutoff(account_handle, project_handle, safe_cleanup_cutoff, renew_lease),
           :ok <-
             maybe_delete_s3_artifacts_with_cutoff(
               account_handle,
               project_handle,
               :xcode_cache,
               "xcode cache",
               safe_cleanup_cutoff,
               renew_lease
             ),
           :ok <- renew_lease.(),
           :ok <-
             delete_s3_artifacts_with_cutoff(
               account_handle,
               project_handle,
               :cache,
               "cache",
               safe_cleanup_cutoff,
               renew_lease
             ),
           :ok <- renew_lease.() do
        tombstoned = DistributedCleanup.tombstone_project_entries(account_handle, project_handle, safe_cleanup_cutoff)

        Logger.info(
          "Distributed cleanup finished for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(safe_cleanup_cutoff)} (tombstoned=#{tombstoned})"
        )

        :ok
      else
        {:error, :cleanup_lease_lost} = error ->
          Logger.warning(
            "Distributed cleanup lease lost for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(safe_cleanup_cutoff)}; aborting so a newer cleanup can continue safely"
          )

          error

        {:error, reason} = error ->
          Logger.error(
            "Distributed cleanup failed for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(safe_cleanup_cutoff)}: #{inspect(reason)}"
          )

          error
      end
    end
  end

  defp invalidate_local_kv(account_handle, project_handle, cutoff) do
    {keys, _count} = KeyValueEntries.delete_project_entries_before(account_handle, project_handle, cutoff)
    Enum.each(keys, &Cachex.del(:cache_keyvalue_store, &1))
    :ok
  end

  defp delete_disk_with_cutoff(account_handle, project_handle, cleanup_started_at, renew_lease) do
    case Disk.delete_project_before(account_handle, project_handle, cleanup_started_at, on_progress: renew_lease) do
      {:ok, count} ->
        Logger.info("Cleaned #{count} disk artifacts for project #{account_handle}/#{project_handle} with cutoff")
        :ok

      {:error, _} = error ->
        error
    end
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

  defp maybe_delete_s3_artifacts_with_cutoff(
         account_handle,
         project_handle,
         :xcode_cache,
         label,
         cleanup_started_at,
         renew_lease
       ) do
    if Config.xcode_cache_bucket() do
      with :ok <- renew_lease.() do
        delete_s3_artifacts_with_cutoff(
          account_handle,
          project_handle,
          :xcode_cache,
          label,
          cleanup_started_at,
          renew_lease
        )
      end
    else
      :ok
    end
  end

  defp maybe_delete_s3_artifacts_with_cutoff(
         account_handle,
         project_handle,
         type,
         label,
         cleanup_started_at,
         renew_lease
       ) do
    with :ok <- renew_lease.() do
      delete_s3_artifacts_with_cutoff(account_handle, project_handle, type, label, cleanup_started_at, renew_lease)
    end
  end

  defp delete_s3_artifacts_with_cutoff(account_handle, project_handle, type, label, cleanup_started_at, renew_lease) do
    prefix = "#{account_handle}/#{project_handle}/"

    case S3.delete_objects_with_prefix_before(prefix, cleanup_started_at, type: type, on_progress: renew_lease) do
      {:ok, count} ->
        Logger.info("Cleaned #{count} S3 #{label} objects with prefix #{prefix} using cutoff-aware deletion")
        :ok

      {:error, :cleanup_lease_lost} = error ->
        error

      {:error, reason} ->
        Logger.error("Failed cutoff-aware S3 #{label} cleanup for prefix #{prefix}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
