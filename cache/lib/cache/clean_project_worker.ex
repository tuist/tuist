defmodule Cache.CleanProjectWorker do
  @moduledoc """
  Oban worker that cleans all cache artifacts for a project from both disk and S3.
  """

  use Oban.Worker, queue: :clean, max_attempts: 3

  alias Cache.Config
  alias Cache.Disk
  alias Cache.DistributedKV.Cleanup
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.S3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"account_handle" => account_handle, "project_handle" => project_handle},
        attempt: attempt
      }) do
    attempt = max(attempt || 0, 1)

    if Config.distributed_kv_enabled?() do
      perform_distributed_cleanup(account_handle, project_handle, attempt)
    else
      perform_local_cleanup(account_handle, project_handle)
      :ok
    end
  end

  defp perform_local_cleanup(account_handle, project_handle) do
    invalidate_local_kv(account_handle, project_handle, DateTime.utc_now())

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

  defp perform_distributed_cleanup(account_handle, project_handle, attempt) do
    case Cleanup.begin_project_cleanup(account_handle, project_handle) do
      {:ok, cleanup_started_at} ->
        safe_cutoff = DateTime.truncate(cleanup_started_at, :second)
        on_progress = fn -> Cleanup.renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at) end

        result =
          with :ok <- invalidate_local_kv(account_handle, project_handle, safe_cutoff),
               :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at),
               :ok <- delete_disk_with_cutoff(account_handle, project_handle, safe_cutoff, on_progress),
               :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at),
               :ok <- maybe_delete_xcode_s3_artifacts(account_handle, project_handle, safe_cutoff, on_progress),
               :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at),
               :ok <-
                 delete_s3_artifacts_with_cutoff(
                   account_handle,
                   project_handle,
                   :cache,
                   "cache",
                   safe_cutoff,
                   on_progress
                 ),
               :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, cleanup_started_at) do
            tombstoned = Cleanup.tombstone_project_entries(account_handle, project_handle, safe_cutoff)

            Logger.info(
              "Distributed cleanup finished for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(safe_cutoff)} (tombstoned=#{tombstoned})"
            )

            :ok
          end

        case result do
          :ok ->
            :ok

          {:error, :cleanup_lease_lost} = error ->
            Logger.warning(
              "Distributed cleanup lease lost for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(safe_cutoff)}; aborting so a newer cleanup can continue safely"
            )

            error

          {:error, reason} = error ->
            Logger.error(
              "Distributed cleanup failed for #{account_handle}/#{project_handle} with cutoff #{DateTime.to_iso8601(safe_cutoff)}: #{inspect(reason)}"
            )

            :ok = Cleanup.expire_project_cleanup_lease(account_handle, project_handle, cleanup_started_at)
            error
        end

      {:error, :cleanup_already_in_progress} ->
        if attempt > 1 do
          Logger.warning(
            "Distributed cleanup already in progress for #{account_handle}/#{project_handle} on retry attempt #{attempt}; returning retryable error"
          )

          {:error, :cleanup_already_in_progress}
        else
          Logger.info(
            "Distributed cleanup already in progress for #{account_handle}/#{project_handle}; skipping duplicate job"
          )

          :ok
        end
    end
  end

  defp invalidate_local_kv(account_handle, project_handle, cutoff) do
    distributed? = Config.distributed_kv_enabled?()
    on_deleted_keys = fn keys -> invalidate_local_kv_keys(keys, distributed?) end

    opts = maybe_include_pending([on_deleted_keys: on_deleted_keys], distributed?)

    {_keys, _count} =
      KeyValueEntries.delete_project_entries_before(account_handle, project_handle, cutoff, opts)

    :ok
  end

  defp maybe_include_pending(opts, true), do: Keyword.put(opts, :include_pending?, true)
  defp maybe_include_pending(opts, false), do: opts

  defp invalidate_local_kv_keys(keys, distributed?) do
    Enum.each(keys, fn key ->
      if distributed?, do: :ok = KeyValueAccessTracker.clear(key)
      {:ok, _deleted?} = Cachex.del(:cache_keyvalue_store, key)
    end)

    :ok
  end

  defp delete_disk_with_cutoff(account_handle, project_handle, cutoff, on_progress) do
    case Disk.delete_project_files_before(account_handle, project_handle, cutoff, on_progress: on_progress) do
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

  defp maybe_delete_xcode_s3_artifacts(account_handle, project_handle, cutoff, on_progress) do
    if Config.xcode_cache_bucket() do
      delete_s3_artifacts_with_cutoff(account_handle, project_handle, :xcode_cache, "xcode cache", cutoff, on_progress)
    else
      :ok
    end
  end

  defp delete_s3_artifacts_with_cutoff(account_handle, project_handle, type, label, cutoff, on_progress) do
    prefix = "#{account_handle}/#{project_handle}/"

    case S3.delete_objects_with_prefix_before(prefix, cutoff, type: type, on_progress: on_progress) do
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
