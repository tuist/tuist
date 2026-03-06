defmodule Cache.KeyValueEvictionWorker do
  @moduledoc """
  Oban worker that evicts key-value entries that haven't been accessed
  within the configured time window (default: 30 days).
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Cache.CASCleanupWorker
  alias Cache.KeyValueEntries
  alias Cache.Repo

  require Logger

  @cleanup_hashes_per_job 500
  @eviction_event [:cache, :kv, :eviction, :complete]
  @default_batch_size 1000
  @default_max_db_size_bytes 25 * 1024 * 1024 * 1024
  @default_hysteresis_release_bytes 23 * 1024 * 1024 * 1024

  @impl Oban.Worker
  def perform(_job) do
    started_at = System.monotonic_time(:millisecond)

    do_perform(started_at)
  end

  defp do_perform(started_at) do
    max_age_days = Application.get_env(:cache, :key_value_eviction_max_age_days, 30)
    max_duration_ms = Application.get_env(:cache, :key_value_eviction_max_duration_ms, 300_000)
    min_retention_days = Application.get_env(:cache, :key_value_eviction_min_retention_days, 1)
    max_db_size_bytes = Application.get_env(:cache, :key_value_max_db_size_bytes, @default_max_db_size_bytes)

    release_bytes =
      Application.get_env(
        :cache,
        :key_value_eviction_hysteresis_release_bytes,
        @default_hysteresis_release_bytes
      )

    case fetch_size_state() do
      {:ok, size_state} ->
        run_result =
          if exceeds_limit?(size_state, max_db_size_bytes) do
            Logger.warning("KV SQLite size exceeds limit, triggering size-based eviction")

            run_size_based_eviction(
              max_age_days,
              min_retention_days,
              max_duration_ms,
              release_bytes,
              %{},
              0
            )
          else
            run_time_based_eviction(max_age_days, max_duration_ms)
          end

        finish_eviction(run_result, started_at, max_age_days)

      {:busy, :size} ->
        emit_busy_and_finish(started_at, :size)
    end
  rescue
    error ->
      if busy_error?(error) do
        emit_busy_and_finish(started_at, :time)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp finish_eviction({trigger, grouped_hashes, count, status}, started_at, max_age_days) do
    maybe_log_status(status, max_age_days)

    Logger.info(
      "Evicted #{count} key-value entries (trigger=#{trigger}, status=#{status}, max_age_days=#{max_age_days})"
    )

    enqueue_cleanup_jobs(grouped_hashes)

    emit_telemetry(trigger, status, count, started_at)

    :ok
  end

  defp emit_busy_and_finish(started_at, trigger) do
    Logger.warning("Key-value eviction skipped due to SQLite lock contention")
    emit_telemetry(trigger, :busy, 0, started_at)
    :ok
  end

  defp run_time_based_eviction(max_age_days, max_duration_ms) do
    {grouped_hashes, count, status} =
      KeyValueEntries.delete_expired(max_age_days,
        max_duration_ms: max_duration_ms,
        batch_size: @default_batch_size
      )

    {:time, grouped_hashes, count, status}
  end

  defp run_size_based_eviction(
         retention_days,
         min_retention_days,
         max_duration_ms,
         release_bytes,
         grouped_hashes_acc,
         count_acc
       ) do
    {grouped_hashes, count, status} =
      KeyValueEntries.delete_expired(retention_days,
        max_duration_ms: max_duration_ms,
        batch_size: @default_batch_size
      )

    merged_hashes = merge_grouped_hashes(grouped_hashes_acc, grouped_hashes)
    total_count = count_acc + count

    case status do
      :time_limit_reached ->
        {:size, merged_hashes, total_count, :time_limit_reached}

      :complete ->
        run_size_maintenance_pass()

        continue_size_based_eviction(
          retention_days,
          min_retention_days,
          max_duration_ms,
          release_bytes,
          merged_hashes,
          total_count
        )
    end
  end

  defp continue_size_based_eviction(
         retention_days,
         min_retention_days,
         max_duration_ms,
         release_bytes,
         merged_hashes,
         total_count
       ) do
    case fetch_size_state() do
      {:busy, :size} ->
        {:size, merged_hashes, total_count, :busy}

      {:ok, size_state} ->
        size_based_next_step(
          size_state,
          retention_days,
          min_retention_days,
          max_duration_ms,
          release_bytes,
          merged_hashes,
          total_count
        )
    end
  end

  defp size_based_next_step(
         size_state,
         retention_days,
         min_retention_days,
         max_duration_ms,
         release_bytes,
         merged_hashes,
         total_count
       ) do
    cond do
      below_release?(size_state, release_bytes) ->
        {:size, merged_hashes, total_count, :complete}

      retention_days <= min_retention_days ->
        Logger.warning("KV SQLite size remains over release watermark at retention floor")
        {:size, merged_hashes, total_count, :floor_limited}

      true ->
        run_size_based_eviction(
          retention_days - 1,
          min_retention_days,
          max_duration_ms,
          release_bytes,
          merged_hashes,
          total_count
        )
    end
  end

  defp run_size_maintenance_pass do
    query!("PRAGMA wal_checkpoint(PASSIVE)")
    query!("PRAGMA incremental_vacuum(1000)")
    :ok
  end

  defp fetch_size_state do
    {:ok,
     %{
       in_use_plus_wal_bytes: in_use_plus_wal_bytes(),
       allocated_plus_wal_bytes: allocated_plus_wal_bytes()
     }}
  rescue
    error ->
      if busy_error?(error) do
        {:busy, :size}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp in_use_plus_wal_bytes do
    page_count = pragma_value!("PRAGMA page_count")
    freelist_count = pragma_value!("PRAGMA freelist_count")
    page_size = pragma_value!("PRAGMA page_size")
    wal_size = wal_file_size(db_path())

    max(page_count - freelist_count, 0) * page_size + wal_size
  end

  defp allocated_plus_wal_bytes do
    path = db_path()
    db_size = file_size(path)
    wal_size = wal_file_size(path)
    db_size + wal_size
  end

  defp pragma_value!(query) do
    %{rows: [[value]]} = query!(query)
    value
  end

  defp query!(query) do
    case Repo.query(query) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp db_path do
    Application.get_env(:cache, Repo)[:database] || "repo.sqlite"
  end

  defp wal_file_size(path), do: file_size("#{path}-wal")

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end

  defp exceeds_limit?(size_state, limit_bytes) do
    size_state.in_use_plus_wal_bytes > limit_bytes or
      size_state.allocated_plus_wal_bytes > limit_bytes
  end

  defp below_release?(size_state, release_bytes) do
    size_state.in_use_plus_wal_bytes <= release_bytes and
      size_state.allocated_plus_wal_bytes <= release_bytes
  end

  defp merge_grouped_hashes(left, right) do
    Map.merge(left, right, fn _scope, left_hashes, right_hashes ->
      (left_hashes ++ right_hashes)
      |> Enum.uniq()
      |> Enum.sort()
    end)
  end

  defp maybe_log_status(:time_limit_reached, _max_age_days) do
    Logger.warning("Key-value eviction reached configured time limit before finishing")
  end

  defp maybe_log_status(_status, _max_age_days), do: :ok

  defp emit_telemetry(trigger, status, entries_deleted, started_at) do
    duration_ms = System.monotonic_time(:millisecond) - started_at

    :telemetry.execute(
      @eviction_event,
      %{entries_deleted: entries_deleted, duration_ms: duration_ms},
      %{trigger: trigger, status: status}
    )
  end

  defp busy_error?(%Exqlite.Error{message: message}) when is_binary(message) do
    String.contains?(message, ["database is locked", "SQLITE_BUSY"])
  end

  defp busy_error?(_), do: false

  defp enqueue_cleanup_jobs(grouped_hashes) do
    Enum.each(grouped_hashes, fn {{account, project}, hashes} ->
      hashes
      |> Enum.chunk_every(@cleanup_hashes_per_job)
      |> Enum.each(fn chunk ->
        case %{"account_handle" => account, "project_handle" => project, "cas_hashes" => chunk}
             |> CASCleanupWorker.new()
             |> Oban.insert() do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to enqueue CAS cleanup for #{account}/#{project}: #{inspect(reason)}")
        end
      end)
    end)
  end
end
