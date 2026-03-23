defmodule Cache.KeyValueReplicationPoller do
  @moduledoc false

  use GenServer

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.SQLiteHelpers

  @completion_event [:cache, :kv, :replication, :poll, :complete]
  @lag_event [:cache, :kv, :replication, :poll, :lag_ms]
  @local_store_event [:cache, :kv, :replication, :local_store, :size_bytes]
  @page_size 1000
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
    maybe_bootstrap()

    started_at = System.monotonic_time(:millisecond)
    lag_cutoff = DateTime.add(DateTime.utc_now(), -Config.distributed_kv_poll_lag_ms(), :millisecond)

    {total_materialized, total_deleted} = drain_pages(lag_cutoff, started_at, {0, 0})

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

  defp drain_pages(lag_cutoff, started_at, totals) do
    if System.monotonic_time(:millisecond) - started_at >= @max_poll_run_ms do
      totals
    else
      {page_size, new_totals} = apply_one_page(lag_cutoff, totals)

      if page_size == @page_size do
        drain_pages(lag_cutoff, started_at, new_totals)
      else
        new_totals
      end
    end
  end

  defp apply_one_page(lag_cutoff, {total_materialized, total_deleted}) do
    watermark = KeyValueEntries.distributed_watermark()

    query =
      Entry
      |> where([entry], entry.updated_at < ^lag_cutoff)
      |> apply_watermark(watermark)
      |> order_by([entry], asc: entry.updated_at, asc: entry.key)
      |> limit(^@page_size)

    rows = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())

    {processed_count, materialized_count, deleted_count, last_processed_row} =
      Enum.reduce_while(rows, {0, 0, 0, nil}, fn row, {processed_acc, materialized_acc, deleted_acc, last_row} ->
        case apply_remote_row(row) do
          {:ok, {:materialized, _status}} ->
            {:cont, {processed_acc + 1, materialized_acc + 1, deleted_acc, row}}

          {:ok, {:deleted, deleted_rows}} ->
            {:cont, {processed_acc + 1, materialized_acc, deleted_acc + deleted_rows, row}}

          {:error, :busy} ->
            {:halt, {processed_acc, materialized_acc, deleted_acc, last_row}}
        end
      end)

    if last_processed_row do
      :ok = KeyValueEntries.put_distributed_watermark(last_processed_row.updated_at, last_processed_row.key)
      emit_lag(last_processed_row.updated_at)
    end

    {processed_count, {total_materialized + materialized_count, total_deleted + deleted_count}}
  end

  defp maybe_bootstrap do
    if is_nil(KeyValueEntries.distributed_watermark()) do
      cutoff = latest_cutoff()
      budget = Application.get_env(:cache, :key_value_max_db_size_bytes, 25 * 1024 * 1024 * 1024)
      current_size = KeyValueEntries.estimated_size_bytes()
      bootstrap_rows(current_size, budget, nil)

      if cutoff do
        :ok = KeyValueEntries.put_distributed_watermark(cutoff.updated_at, cutoff.key)
      end
    end
  end

  defp latest_cutoff do
    Entry
    |> order_by([entry], desc: entry.updated_at, desc: entry.key)
    |> limit(1)
    |> Repo.one(timeout: Config.distributed_kv_database_timeout_ms())
  end

  defp bootstrap_rows(current_size, budget, _cursor) when current_size >= budget, do: :ok

  defp bootstrap_rows(current_size, budget, cursor) do
    query =
      Entry
      |> where([entry], is_nil(entry.deleted_at))
      |> apply_bootstrap_cursor(cursor)
      |> order_by([entry], desc: entry.last_accessed_at, desc: entry.key)
      |> limit(^@bootstrap_page_size)

    rows = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())

    case rows do
      [] ->
        :ok

      _ ->
        {status, size_after_page} =
          Enum.reduce_while(rows, {:ok, current_size}, &materialize_bootstrap_row(&1, &2, budget))

        if status == :ok do
          last_row = List.last(rows)
          bootstrap_rows(size_after_page, budget, {last_row.last_accessed_at, last_row.key})
        else
          :ok
        end
    end
  end

  defp materialize_bootstrap_row(row, {:ok, size_acc}, budget) do
    if size_acc >= budget do
      {:halt, {:ok, size_acc}}
    else
      case materialize_remote_row(row) do
        {:ok, status} ->
          if status in [:inserted, :payload_updated], do: KeyValueAccessTracker.mark_shared_lineage(row.key)
          {:cont, {:ok, size_acc + byte_size(row.json_payload)}}

        {:error, :busy} ->
          {:halt, {:busy, size_acc}}
      end
    end
  end

  defp apply_remote_row(%Entry{deleted_at: nil} = row) do
    case materialize_remote_row(row) do
      {:ok, status} ->
        if status in [:inserted, :payload_updated] do
          Cachex.del(:cache_keyvalue_store, row.key)
        end

        KeyValueAccessTracker.mark_shared_lineage(row.key)
        {:ok, {:materialized, status}}

      {:error, :busy} ->
        {:error, :busy}
    end
  end

  defp apply_remote_row(row) do
    case delete_remote_row(row) do
      {:ok, deleted_rows} ->
        Cachex.del(:cache_keyvalue_store, row.key)
        KeyValueAccessTracker.clear(row.key)
        {:ok, {:deleted, deleted_rows}}

      {:error, :busy} ->
        {:error, :busy}
    end
  end

  defp materialize_remote_row(row) do
    {:ok,
     KeyValueEntries.materialize_remote_entry(%{
       key: row.key,
       json_payload: row.json_payload,
       last_accessed_at: row.last_accessed_at,
       source_updated_at: row.source_updated_at,
       source_node: row.source_node
     })}
  rescue
    error ->
      if SQLiteHelpers.busy_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp delete_remote_row(row) do
    {:ok, KeyValueEntries.delete_local_entry_if_not_pending(row.key)}
  rescue
    error ->
      if SQLiteHelpers.busy_error?(error) do
        {:error, :busy}
      else
        reraise error, __STACKTRACE__
      end
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

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end
end
