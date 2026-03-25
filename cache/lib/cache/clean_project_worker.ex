defmodule Cache.CleanProjectWorker do
  @moduledoc """
  Oban worker that cleans all cache artifacts for a project from both disk and S3.
  """

  use Oban.Worker, queue: :clean, max_attempts: 3

  alias Cache.CacheArtifacts
  alias Cache.Config
  alias Cache.Disk
  alias Cache.DistributedKV.Cleanup
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueStore
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
    :ok = delete_project_kv_entries(account_handle, project_handle, DateTime.utc_now(), fn -> :ok end)

    case Disk.delete_project(account_handle, project_handle) do
      :ok ->
        :ok = CacheArtifacts.delete_by_project(account_handle, project_handle)
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
      {:ok, active_cleanup_cutoff_at} ->
        perform_primary_distributed_cleanup(account_handle, project_handle, active_cleanup_cutoff_at)

      {:error, :cleanup_already_in_progress} ->
        perform_duplicate_distributed_cleanup(account_handle, project_handle, attempt)
    end
  end

  defp perform_primary_distributed_cleanup(account_handle, project_handle, active_cleanup_cutoff_at) do
    safe_cutoff = DateTime.truncate(active_cleanup_cutoff_at, :second)

    check_lease = fn ->
      Cleanup.renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at)
    end

    result =
      with :ok <- perform_local_node_cleanup(account_handle, project_handle, safe_cutoff, check_lease),
           :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at),
           :ok <- maybe_delete_xcode_s3_artifacts(account_handle, project_handle, safe_cutoff, check_lease),
           :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at),
           :ok <-
             delete_s3_artifacts_with_cutoff(
               account_handle,
               project_handle,
               :cache,
               "cache",
               safe_cutoff,
               check_lease
             ),
           :ok <- Cleanup.renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at),
           {:ok, published} <- Cleanup.publish_project_cleanup(account_handle, project_handle, active_cleanup_cutoff_at) do
        :ok =
          put_local_applied_generation_after_publish(
            account_handle,
            project_handle,
            published.published_cleanup_generation
          )

        Logger.info(
          "Distributed cleanup published for #{account_handle}/#{project_handle} " <>
            "with cutoff #{DateTime.to_iso8601(safe_cutoff)} " <>
            "(generation=#{published.published_cleanup_generation}, event_id=#{published.cleanup_event_id})"
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

        :ok = Cleanup.expire_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at)
        error
    end
  end

  defp perform_duplicate_distributed_cleanup(account_handle, project_handle, attempt) do
    with {:ok, cleanup_cutoff} <- existing_cleanup_cutoff(account_handle, project_handle),
         :ok <- perform_local_node_cleanup(account_handle, project_handle, cleanup_cutoff, fn -> :ok end) do
      if attempt > 1 do
        Logger.warning(
          "Distributed cleanup already in progress for #{account_handle}/#{project_handle} on retry attempt #{attempt}; completed node-local cleanup with cutoff #{DateTime.to_iso8601(cleanup_cutoff)} and returning retryable error"
        )

        {:error, :cleanup_already_in_progress}
      else
        Logger.info(
          "Distributed cleanup already in progress for #{account_handle}/#{project_handle}; completed node-local cleanup with cutoff #{DateTime.to_iso8601(cleanup_cutoff)}"
        )

        :ok
      end
    end
  end

  defp existing_cleanup_cutoff(account_handle, project_handle) do
    case Cleanup.latest_project_cleanup_cutoff(account_handle, project_handle) do
      %DateTime{} = cleanup_cutoff ->
        {:ok, cleanup_cutoff}

      nil ->
        Logger.error(
          "Distributed cleanup is marked in progress for #{account_handle}/#{project_handle}, but no shared cleanup cutoff exists"
        )

        {:error, :cleanup_cutoff_not_found}
    end
  end

  @doc false
  def perform_local_node_cleanup(account_handle, project_handle, cutoff, check_lease) do
    with :ok <- delete_project_kv_entries(account_handle, project_handle, cutoff, check_lease) do
      delete_disk_with_cutoff(account_handle, project_handle, cutoff, check_lease)
    end
  end

  defp delete_project_kv_entries(account_handle, project_handle, cutoff, check_lease) do
    opts =
      [after_delete_batch: fn _keys -> check_lease.() end, on_deleted_keys: &invalidate_kv_cache_keys/1]

    opts =
      if Config.distributed_kv_enabled?() do
        Keyword.put(opts, :include_pending, true)
      else
        opts
      end

    case KeyValueEntries.delete_project_entries_before(account_handle, project_handle, cutoff, opts) do
      {:error, reason} -> {:error, reason}
      {_keys, _count} -> :ok
    end
  end

  defp invalidate_kv_cache_keys(keys) do
    distributed? = Config.distributed_kv_enabled?()

    Enum.each(keys, fn key ->
      if distributed?, do: :ok = KeyValueAccessTracker.clear(key)
      {:ok, _deleted?} = Cachex.del(KeyValueStore.cache_name(), key)
    end)

    :ok
  end

  defp put_local_applied_generation_after_publish(account_handle, project_handle, generation) do
    Cleanup.put_local_applied_generation(account_handle, project_handle, generation)
  rescue
    error in [Exqlite.Error, Ecto.StaleEntryError, DBConnection.ConnectionError, RuntimeError] ->
      Logger.warning(
        "Distributed cleanup was already published for #{account_handle}/#{project_handle}, " <>
          "but persisting the local applied generation failed: #{inspect(error)}"
      )

      :ok
  end

  defp delete_disk_with_cutoff(account_handle, project_handle, cutoff, check_lease) do
    on_deleted_keys = fn keys -> CacheArtifacts.delete_by_keys(keys) end

    case Disk.delete_project_files_before(account_handle, project_handle, cutoff,
           check_lease: check_lease,
           on_deleted_keys: on_deleted_keys
         ) do
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

  defp maybe_delete_xcode_s3_artifacts(account_handle, project_handle, cutoff, check_lease) do
    if Config.xcode_cache_bucket() do
      delete_s3_artifacts_with_cutoff(account_handle, project_handle, :xcode_cache, "xcode cache", cutoff, check_lease)
    else
      :ok
    end
  end

  defp delete_s3_artifacts_with_cutoff(account_handle, project_handle, type, label, cutoff, check_lease) do
    prefix = "#{account_handle}/#{project_handle}/"

    case S3.delete_objects_with_prefix_before(prefix, cutoff, type: type, check_lease: check_lease) do
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
