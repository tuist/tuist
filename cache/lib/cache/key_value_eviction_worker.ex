defmodule Cache.KeyValueEvictionWorker do
  @moduledoc """
  Oban worker that evicts key-value entries that haven't been accessed
  within the configured time window (default: 30 days).

  A single worker-level deadline governs all DB-facing work: size checks,
  eviction passes, and maintenance PRAGMAs. When the deadline is exhausted
  the worker stops DB work but still enqueues CAS cleanup for any hashes
  already deleted.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Cache.CASCleanupWorker
  alias Cache.Config
  alias Cache.KeyValueEntries
  alias Cache.KeyValueRepo

  require Logger

  @cleanup_hashes_per_job 500
  @eviction_event [:cache, :kv, :eviction, :complete]
  @default_batch_size 1000
  @default_max_db_size_bytes 25 * 1024 * 1024 * 1024
  @default_hysteresis_release_bytes 23 * 1024 * 1024 * 1024

  @impl Oban.Worker
  def perform(_job) do
    started_at = System.monotonic_time(:millisecond)
    deadline_ms = started_at + Config.key_value_eviction_max_duration_ms()

    do_perform(started_at, deadline_ms)
  end

  defp do_perform(started_at, deadline_ms) do
    max_age_days = Application.get_env(:cache, :key_value_eviction_max_age_days, 30)
    min_retention_days = Application.get_env(:cache, :key_value_eviction_min_retention_days, 1)
    max_db_size_bytes = Application.get_env(:cache, :key_value_max_db_size_bytes, @default_max_db_size_bytes)

    release_bytes =
      Application.get_env(
        :cache,
        :key_value_eviction_hysteresis_release_bytes,
        @default_hysteresis_release_bytes
      )

    case fetch_size_state(deadline_ms) do
      {:ok, size_state} ->
        run_result =
          if exceeds_limit?(size_state, max_db_size_bytes) do
            Logger.warning("KV SQLite size exceeds limit, triggering size-based eviction")
            run_size_based_eviction(min_retention_days, deadline_ms, release_bytes)
          else
            run_time_based_eviction(max_age_days, deadline_ms)
          end

        finish_eviction(run_result, started_at, max_age_days)

      {:error, :busy} ->
        emit_busy_and_finish(started_at, :size)

      {:error, :deadline_exhausted} ->
        finish_eviction({:time, %{}, 0, :time_limit_reached}, started_at, max_age_days)
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

  defp run_time_based_eviction(max_age_days, deadline_ms) do
    if deadline_reached?(deadline_ms) do
      {:time, %{}, 0, :time_limit_reached}
    else
      {grouped_hashes, count, status} =
        KeyValueEntries.delete_expired(max_age_days,
          max_duration_ms: remaining_time(deadline_ms),
          batch_size: @default_batch_size
        )

      {:time, grouped_hashes, count, status}
    end
  end

  # Single oldest-first batched eviction loop. Each iteration deletes one
  # batch, runs a maintenance pass, and re-checks DB size before continuing.
  defp run_size_based_eviction(min_retention_days, deadline_ms, release_bytes) do
    size_eviction_loop(min_retention_days, deadline_ms, release_bytes, %{}, 0)
  end

  defp size_eviction_loop(min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc) do
    if deadline_reached?(deadline_ms) do
      Logger.warning("Key-value size eviction reached worker deadline")
      {:size, hashes_acc, count_acc, :time_limit_reached}
    else
      {batch_hashes, batch_count, batch_status} =
        KeyValueEntries.delete_one_expired_batch(min_retention_days,
          batch_size: @default_batch_size,
          max_duration_ms: remaining_time(deadline_ms)
        )

      merged_hashes = merge_grouped_hashes(hashes_acc, batch_hashes)
      total_count = count_acc + batch_count

      case batch_status do
        :busy ->
          {:size, merged_hashes, total_count, :busy}

        :time_limit_reached ->
          {:size, merged_hashes, total_count, :time_limit_reached}

        :complete ->
          if batch_count == 0 do
            Logger.warning("KV SQLite size remains over release watermark at retention floor")
            {:size, merged_hashes, total_count, :floor_limited}
          else
            after_batch_step(min_retention_days, deadline_ms, release_bytes, merged_hashes, total_count)
          end
      end
    end
  end

  defp after_batch_step(min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc) do
    if deadline_reached?(deadline_ms) do
      Logger.warning("Key-value size eviction reached worker deadline after batch")
      {:size, hashes_acc, count_acc, :time_limit_reached}
    else
      case run_size_maintenance_pass(deadline_ms) do
        :ok ->
          continue_size_eviction(min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc)

        {:error, :busy} ->
          {:size, hashes_acc, count_acc, :busy}

        {:error, :deadline_exhausted} ->
          {:size, hashes_acc, count_acc, :time_limit_reached}
      end
    end
  end

  defp continue_size_eviction(min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc) do
    case fetch_size_state(deadline_ms) do
      {:ok, size_state} ->
        maybe_finish_size_eviction(size_state, min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc)

      {:error, :busy} ->
        {:size, hashes_acc, count_acc, :busy}

      {:error, :deadline_exhausted} ->
        {:size, hashes_acc, count_acc, :time_limit_reached}
    end
  end

  defp maybe_finish_size_eviction(size_state, min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc) do
    if below_release?(size_state, release_bytes) do
      {:size, hashes_acc, count_acc, :complete}
    else
      size_eviction_loop(min_retention_days, deadline_ms, release_bytes, hashes_acc, count_acc)
    end
  end

  defp run_size_maintenance_pass(deadline_ms) do
    with_db_budget(deadline_ms, fn ->
      query!("PRAGMA wal_checkpoint(PASSIVE)")
      query!("PRAGMA incremental_vacuum(1000)")
      :ok
    end)
  end

  defp fetch_size_state(deadline_ms) do
    with_db_budget(deadline_ms, fn ->
      {:ok,
       %{
         in_use_plus_wal_bytes: in_use_plus_wal_bytes(),
         allocated_plus_wal_bytes: allocated_plus_wal_bytes()
       }}
    end)
  end

  defp with_db_budget(deadline_ms, fun) do
    if deadline_reached?(deadline_ms) do
      {:error, :deadline_exhausted}
    else
      KeyValueRepo.checkout(fn ->
        try do
          set_busy_timeout!(remaining_time(deadline_ms))
          fun.()
        rescue
          error ->
            if busy_error?(error) do
              {:error, :busy}
            else
              reraise error, __STACKTRACE__
            end
        after
          restore_busy_timeout!()
        end
      end)
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
    case KeyValueRepo.query(query) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp db_path do
    Application.get_env(:cache, KeyValueRepo)[:database] || "key_value.sqlite"
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

  defp deadline_reached?(deadline_ms) do
    System.monotonic_time(:millisecond) >= deadline_ms
  end

  defp remaining_time(deadline_ms) do
    max(deadline_ms - System.monotonic_time(:millisecond), 0)
  end

  defp set_busy_timeout!(timeout_ms) do
    case KeyValueRepo.query("PRAGMA busy_timeout = #{max(timeout_ms, 0)}") do
      {:ok, _result} -> :ok
      {:error, error} -> raise error
    end
  end

  defp restore_busy_timeout! do
    set_busy_timeout!(Config.repo_busy_timeout_ms(KeyValueRepo))
  rescue
    _ -> :ok
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
