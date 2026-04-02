defmodule Cache.KeyValueReplicationPoller do
  @moduledoc false

  use GenServer

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueStore

  require Logger

  @completion_event [:cache, :kv, :replication, :poll, :complete]
  @lag_event [:cache, :kv, :replication, :poll, :lag_ms]
  @local_store_event [:cache, :kv, :replication, :local_store, :size_bytes]
  @page_size 1000
  @apply_chunk_size 100
  @bootstrap_page_size 500
  @max_poll_run_ms 10_000
  @local_store_emit_interval_ms to_timeout(minute: 10)
  @max_backoff_ms 30_000
  @base_backoff_ms 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def poll_now do
    GenServer.call(__MODULE__, :poll, :infinity)
  end

  @impl true
  def init(_opts) do
    schedule_poll(0)
    {:ok, %{last_local_store_size_emitted_at_ms: nil, consecutive_errors: 0}}
  end

  @impl true
  def handle_call(:poll, _from, state) do
    {result, new_state} = safe_poll(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    {_result, new_state} = safe_poll(state)

    delay =
      if new_state.consecutive_errors > 0 do
        min(@base_backoff_ms * Integer.pow(2, min(new_state.consecutive_errors - 1, 14)), @max_backoff_ms)
      else
        Config.distributed_kv_sync_interval_ms()
      end

    schedule_poll(delay)
    {:noreply, new_state}
  end

  defp safe_poll(state) do
    case poll_once(state) do
      {:ok, new_state} ->
        {:ok, %{new_state | consecutive_errors: 0}}

      {:error, reason} ->
        poll_error_result(state, reason)
    end
  rescue
    error ->
      poll_error_result(state, error)
  end

  defp poll_once(state) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, {total_materialized, total_deleted}} <- poll_totals(started_at) do
      new_state = maybe_emit_local_store_size(state)

      :telemetry.execute(
        @completion_event,
        %{
          duration_ms: System.monotonic_time(:millisecond) - started_at,
          rows_materialized: total_materialized,
          rows_deleted: total_deleted
        },
        %{}
      )

      {:ok, new_state}
    end
  end

  defp poll_totals(started_at) do
    case maybe_bootstrap() do
      :ok ->
        watermark = KeyValueEntries.distributed_watermark()
        drain_pages(watermark, started_at, {0, 0})

      :busy ->
        {:ok, {0, 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll_error_result(state, reason) do
    Logger.error("Replication poller poll failed: #{format_poll_error(reason)}")

    :telemetry.execute(
      @completion_event,
      %{duration_ms: 0, rows_materialized: 0, rows_deleted: 0},
      %{status: :error}
    )

    {{:error, reason}, %{state | consecutive_errors: state.consecutive_errors + 1}}
  end

  defp format_poll_error(error) when is_exception(error), do: Exception.message(error)
  defp format_poll_error(reason), do: inspect(reason)

  defp drain_pages(watermark, started_at, totals) do
    if System.monotonic_time(:millisecond) - started_at >= @max_poll_run_ms do
      {:ok, totals}
    else
      case apply_one_page(watermark, totals) do
        {:ok, {continue?, new_watermark, new_totals}} ->
          if continue? do
            drain_pages(new_watermark, started_at, new_totals)
          else
            {:ok, new_totals}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp apply_one_page(watermark, {total_materialized, total_deleted}) do
    query =
      Entry
      |> apply_poll_lag_filter()
      |> apply_watermark(watermark)
      |> order_by([entry], asc: entry.updated_at, asc: entry.key)
      |> limit(^@page_size)

    fetched_rows = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())
    rows = filter_rows_against_published_barriers(fetched_rows)

    case rows
         |> Enum.chunk_every(@apply_chunk_size)
         |> Enum.reduce_while({:ok, {0, 0, 0}}, fn chunk, {:ok, {processed_acc, materialized_acc, deleted_acc}} ->
           case apply_remote_chunk(chunk) do
             {:ok, result} ->
               {:cont,
                {:ok,
                 {processed_acc + result.processed_count, materialized_acc + alive_row_count(chunk),
                  deleted_acc + result.deleted_count}}}

             {:error, :busy} ->
               {:halt, {:ok, {processed_acc, materialized_acc, deleted_acc}}}

             {:error, reason} ->
               {:halt, {:error, reason}}
           end
         end) do
      {:error, reason} ->
        {:error, reason}

      {:ok, {processed_count, materialized_count, deleted_count}} ->
        last_processed = last_processed_row(rows, processed_count)
        last_advanceable = last_advanceable_row(fetched_rows, rows, processed_count)

        :ok = persist_watermark_advance(last_processed, last_advanceable)

        new_watermark =
          if last_advanceable do
            %{watermark_updated_at: last_advanceable.updated_at, watermark_key: last_advanceable.key}
          else
            watermark
          end

        continue? =
          length(fetched_rows) == @page_size and processed_count == length(rows) and not is_nil(last_advanceable)

        {:ok, {continue?, new_watermark, {total_materialized + materialized_count, total_deleted + deleted_count}}}
    end
  end

  defp last_advanceable_row([], _filtered_rows, _processed_count), do: nil

  defp last_advanceable_row(fetched_rows, filtered_rows, processed_count) do
    filtered_keys = MapSet.new(Enum.map(filtered_rows, & &1.key))

    fetched_rows
    |> Enum.reduce_while({0, nil}, fn row, {processed_filtered, last_advanceable} ->
      if MapSet.member?(filtered_keys, row.key) do
        if processed_filtered < processed_count do
          {:cont, {processed_filtered + 1, row}}
        else
          {:halt, {processed_filtered, last_advanceable}}
        end
      else
        {:cont, {processed_filtered, row}}
      end
    end)
    |> elem(1)
  end

  defp last_processed_row(_rows, 0), do: nil

  defp last_processed_row(rows, processed_count) do
    rows |> Enum.take(processed_count) |> List.last()
  end

  defp persist_watermark_advance(nil, nil), do: :ok

  defp persist_watermark_advance(nil, last_advanceable) do
    KeyValueEntries.put_distributed_watermark(last_advanceable.updated_at, last_advanceable.key)
  end

  defp persist_watermark_advance(_last_processed, nil), do: :ok

  defp persist_watermark_advance(last_processed, last_advanceable) do
    if same_row?(last_processed, last_advanceable) do
      :ok
    else
      KeyValueEntries.put_distributed_watermark(last_advanceable.updated_at, last_advanceable.key)
    end
  end

  defp same_row?(nil, nil), do: true
  defp same_row?(nil, _row), do: false
  defp same_row?(_row, nil), do: false

  defp same_row?(left, right) do
    left.key == right.key and DateTime.compare(left.updated_at, right.updated_at) == :eq
  end

  defp maybe_bootstrap do
    if is_nil(KeyValueEntries.distributed_watermark()) do
      cutoff = latest_cutoff()
      budget = Application.get_env(:cache, :key_value_max_db_size_bytes, 25 * 1024 * 1024 * 1024)
      current_size = KeyValueEntries.estimated_size_bytes()

      case bootstrap_rows(current_size, budget, nil) do
        :complete ->
          if cutoff do
            :ok = KeyValueEntries.put_distributed_watermark(cutoff.updated_at, cutoff.key)
          end

          :ok

        :busy ->
          :busy

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end

  defp latest_cutoff do
    Entry
    |> order_by([entry], desc: entry.updated_at, desc: entry.key)
    |> limit(1)
    |> Repo.one(timeout: Config.distributed_kv_database_timeout_ms())
  end

  defp bootstrap_rows(current_size, budget, _cursor) when current_size >= budget, do: :complete

  defp bootstrap_rows(current_size, budget, cursor) do
    query =
      Entry
      |> where([entry], is_nil(entry.deleted_at))
      |> apply_bootstrap_cursor(cursor)
      |> order_by([entry], desc: entry.last_accessed_at, desc: entry.key)
      |> limit(^@bootstrap_page_size)

    fetched_rows = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())
    rows = filter_rows_against_published_barriers(fetched_rows)

    case fetched_rows do
      [] ->
        :complete

      _ ->
        {rows_to_materialize, size_after_page} = bootstrap_materializable_rows(rows, current_size, budget)

        case materialize_bootstrap_rows(rows_to_materialize) do
          :ok ->
            last_row = List.last(fetched_rows)
            bootstrap_rows(size_after_page, budget, {last_row.last_accessed_at, last_row.key})

          :busy ->
            :busy

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp bootstrap_materializable_rows(rows, current_size, budget) do
    {selected, final_size} =
      Enum.reduce_while(rows, {[], current_size}, fn row, {selected_rows, size_acc} ->
        if size_acc >= budget do
          {:halt, {selected_rows, size_acc}}
        else
          {:cont, {[row | selected_rows], size_acc + byte_size(row.json_payload)}}
        end
      end)

    {Enum.reverse(selected), final_size}
  end

  defp materialize_bootstrap_rows(rows) do
    rows
    |> Enum.chunk_every(@apply_chunk_size)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case KeyValueEntries.materialize_remote_entries(chunk) do
        {:ok, result} ->
          Enum.each(result.invalidate_keys, &KeyValueAccessTracker.mark_shared_lineage/1)
          {:cont, :ok}

        {:error, :busy} ->
          {:halt, :busy}

        {:error, reason} ->
          {:halt, {:error, {:bootstrap_apply_failed, reason}}}
      end
    end)
  end

  defp apply_remote_chunk(rows) do
    case KeyValueEntries.apply_remote_batch(rows) do
      {:ok, result} ->
        :ok = run_chunk_side_effects(result)
        :ok = KeyValueEntries.commit_remote_batch(result.last_processed_row)
        emit_chunk_lag(result.last_processed_row)
        {:ok, result}

      {:error, :busy} ->
        {:error, :busy}

      {:error, reason} ->
        {:error, {:remote_batch_apply_failed, reason}}
    end
  end

  defp run_chunk_side_effects(result) do
    Enum.each(result.invalidate_keys, fn key ->
      {:ok, _deleted?} = Cachex.del(KeyValueStore.cache_name(), key)
    end)

    Enum.each(result.mark_lineage_keys, fn key ->
      :ok = KeyValueAccessTracker.mark_shared_lineage(key)
    end)

    Enum.each(result.clear_lineage_keys, fn key ->
      :ok = KeyValueAccessTracker.clear(key)
    end)

    :ok
  end

  defp emit_chunk_lag(nil), do: :ok
  defp emit_chunk_lag(last_processed_row), do: emit_lag(last_processed_row.updated_at)

  defp alive_row_count(rows) do
    Enum.count(rows, &is_nil(&1.deleted_at))
  end

  defp apply_poll_lag_filter(query) do
    lag_ms = Config.distributed_kv_poll_lag_ms()

    from(entry in query,
      where:
        entry.updated_at <
          fragment("(clock_timestamp() - (? * INTERVAL '1 millisecond'))::timestamp", ^lag_ms)
    )
  end

  defp apply_watermark(query, nil), do: query

  defp apply_watermark(query, watermark) do
    watermark_updated_at = watermark.watermark_updated_at || ~U[1970-01-01 00:00:00Z]
    watermark_key = watermark.watermark_key || ""

    from(entry in query,
      where:
        entry.updated_at > ^watermark_updated_at or
          (entry.updated_at == ^watermark_updated_at and entry.key > ^watermark_key)
    )
  end

  defp apply_bootstrap_cursor(query, nil), do: query

  defp apply_bootstrap_cursor(query, {last_accessed_at, key}) do
    from(entry in query,
      where:
        entry.last_accessed_at < ^last_accessed_at or
          (entry.last_accessed_at == ^last_accessed_at and entry.key < ^key)
    )
  end

  defp emit_lag(updated_at) do
    lag_ms = DateTime.diff(DateTime.utc_now(), updated_at, :millisecond)
    :telemetry.execute(@lag_event, %{lag_ms: lag_ms}, %{})
  end

  defp maybe_emit_local_store_size(%{last_local_store_size_emitted_at_ms: last_emitted_at_ms} = state) do
    now_ms = System.monotonic_time(:millisecond)

    if is_nil(last_emitted_at_ms) or now_ms - last_emitted_at_ms >= @local_store_emit_interval_ms do
      size_bytes = KeyValueEntries.estimated_size_bytes()

      emit_local_store_size(size_bytes)

      %{state | last_local_store_size_emitted_at_ms: now_ms}
    else
      state
    end
  end

  defp emit_local_store_size(size_bytes) do
    :telemetry.execute(
      @local_store_event,
      %{size_bytes: size_bytes},
      %{node: Config.distributed_kv_node_name(), region: Config.deploy_region()}
    )
  end

  defp filter_rows_against_published_barriers([]), do: []

  defp filter_rows_against_published_barriers(rows) do
    scope_pairs =
      rows
      |> Enum.map(fn row -> {row.account_handle, row.project_handle} end)
      |> Enum.uniq()

    barriers = Cleanup.published_cleanup_barriers_for_projects(scope_pairs)

    if barriers == %{} do
      rows
    else
      Enum.reject(rows, fn row ->
        case Map.get(barriers, {row.account_handle, row.project_handle}) do
          nil ->
            false

          published_cutoff ->
            DateTime.compare(row.source_updated_at, published_cutoff) in [:lt, :eq]
        end
      end)
    end
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end
end
