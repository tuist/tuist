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

  @completion_event [:cache, :kv, :replication, :poll, :complete]
  @lag_event [:cache, :kv, :replication, :poll, :lag_ms]
  @local_store_event [:cache, :kv, :replication, :local_store, :size_bytes]
  @page_size 1000
  @apply_chunk_size 100
  @bootstrap_page_size 500
  @max_poll_run_ms 10_000
  @local_store_emit_interval_ms 10 * 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def poll_now do
    GenServer.call(__MODULE__, :poll, :infinity)
  end

  @impl true
  def init(_opts) do
    schedule_poll(0)
    {:ok, %{last_local_store_size_emitted_at_ms: nil}}
  end

  @impl true
  def handle_call(:poll, _from, state) do
    {result, new_state} = poll_once(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    {_result, new_state} = poll_once(state)
    schedule_poll(Config.distributed_kv_sync_interval_ms())
    {:noreply, new_state}
  end

  defp poll_once(state) do
    started_at = System.monotonic_time(:millisecond)

    {total_materialized, total_deleted} =
      case maybe_bootstrap() do
        :ok ->
          watermark = KeyValueEntries.distributed_watermark()
          drain_pages(watermark, started_at, {0, 0})

        :busy ->
          {0, 0}
      end

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

  defp drain_pages(watermark, started_at, totals) do
    if System.monotonic_time(:millisecond) - started_at >= @max_poll_run_ms do
      totals
    else
      {page_size, new_watermark, new_totals} = apply_one_page(watermark, totals)

      if page_size == @page_size do
        drain_pages(new_watermark, started_at, new_totals)
      else
        new_totals
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

    rows = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())
    rows = filter_rows_against_published_barriers(rows)

    {processed_count, materialized_count, deleted_count} =
      rows
      |> Enum.chunk_every(@apply_chunk_size)
      |> Enum.reduce_while({0, 0, 0}, fn chunk, {processed_acc, materialized_acc, deleted_acc} ->
        case apply_remote_chunk(chunk) do
          {:ok, result} ->
            {:cont,
             {processed_acc + result.processed_count, materialized_acc + alive_row_count(chunk),
              deleted_acc + result.deleted_count}}

          {:error, :busy} ->
            {:halt, {processed_acc, materialized_acc, deleted_acc}}
        end
      end)

    last_committed = last_committed_row(rows, processed_count)

    new_watermark =
      if last_committed do
        %{updated_at_value: last_committed.updated_at, key_value: last_committed.key}
      else
        watermark
      end

    {processed_count, new_watermark, {total_materialized + materialized_count, total_deleted + deleted_count}}
  end

  defp last_committed_row(_rows, 0), do: nil

  defp last_committed_row(rows, processed_count) do
    rows |> Enum.take(processed_count) |> List.last()
  end

  defp maybe_bootstrap do
    if is_nil(KeyValueEntries.distributed_watermark()) do
      cutoff = latest_cutoff()
      budget = Application.get_env(:cache, :key_value_max_db_size_bytes, 25 * 1024 * 1024 * 1024)
      current_size = KeyValueEntries.estimated_size_bytes()
      bootstrap_status = bootstrap_rows(current_size, budget, nil)

      if cutoff && bootstrap_status == :complete do
        :ok = KeyValueEntries.put_distributed_watermark(cutoff.updated_at, cutoff.key)
      end

      if bootstrap_status == :busy, do: :busy, else: :ok
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

    rows = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())
    rows = filter_rows_against_published_barriers(rows)

    case rows do
      [] ->
        :complete

      _ ->
        {rows_to_materialize, size_after_page} = bootstrap_materializable_rows(rows, current_size, budget)

        status = materialize_bootstrap_rows(rows_to_materialize)

        if status == :ok do
          last_row = List.last(rows)
          bootstrap_rows(size_after_page, budget, {last_row.last_accessed_at, last_row.key})
        else
          :busy
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
          raise "unexpected bootstrap apply error: #{inspect(reason)}"
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
        raise "unexpected remote batch apply error: #{inspect(reason)}"
    end
  end

  defp run_chunk_side_effects(result) do
    Enum.each(result.invalidate_keys, fn key ->
      {:ok, _deleted?} = Cachex.del(:cache_keyvalue_store, key)
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
    updated_at_value = watermark.updated_at_value || ~U[1970-01-01 00:00:00Z]
    key_value = watermark.key_value || ""

    from(entry in query,
      where:
        entry.updated_at > ^updated_at_value or
          (entry.updated_at == ^updated_at_value and entry.key > ^key_value)
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
      %{node: Config.distributed_kv_node_name(), region: System.get_env("DEPLOY_REGION") || "unknown"}
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
