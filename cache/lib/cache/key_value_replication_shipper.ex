defmodule Cache.KeyValueReplicationShipper do
  @moduledoc false

  use GenServer

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueStore

  require Logger

  @telemetry_event [:cache, :kv, :replication, :ship, :flush]
  @pending_rows_event [:cache, :kv, :replication, :ship, :pending_rows]
  @shared_insert_types %{
    key: :string,
    account_handle: :string,
    project_handle: :string,
    cas_id: :string,
    json_payload: :string,
    source_node: :string,
    source_updated_at: :utc_datetime_usec,
    last_accessed_at: :utc_datetime_usec
  }
  @shared_touch_types %{
    key: :string,
    last_accessed_at: :utc_datetime_usec
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def flush_now do
    GenServer.call(__MODULE__, :flush, :infinity)
  end

  @max_backoff_ms 30_000
  @base_backoff_ms 1_000

  @impl true
  def init(_opts) do
    schedule_flush(0)
    {:ok, %{consecutive_errors: 0}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {result, new_state} = safe_flush(state)

    reply =
      case result do
        {:ok, _stats} -> :ok
        {:error, error} -> {:error, error}
      end

    {:reply, reply, new_state}
  end

  @impl true
  def handle_info(:flush, state) do
    {result, new_state} = safe_flush(state)

    delay =
      if new_state.consecutive_errors > 0 do
        min(@base_backoff_ms * Integer.pow(2, min(new_state.consecutive_errors - 1, 14)), @max_backoff_ms)
      else
        case result do
          {:ok, %{batch_full?: true}} -> 0
          _ -> Config.distributed_kv_ship_interval_ms()
        end
      end

    schedule_flush(delay)
    {:noreply, new_state}
  end

  def handle_info(message, state) do
    Logger.warning("Replication shipper received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  defp safe_flush(state) do
    flush_result = flush_pending_rows()
    {{:ok, flush_result}, %{state | consecutive_errors: 0}}
  rescue
    error ->
      Logger.error("Replication shipper flush failed: #{Exception.message(error)}")

      :telemetry.execute(
        @telemetry_event,
        %{duration_ms: 0, batch_size: 0},
        %{status: :error}
      )

      {{:error, error}, %{state | consecutive_errors: state.consecutive_errors + 1}}
  end

  defp flush_pending_rows do
    pending_rows = KeyValueEntries.list_pending_replication()
    pending_count = length(pending_rows)
    batch_size = Config.distributed_kv_ship_batch_size()
    :telemetry.execute(@pending_rows_event, %{count: pending_count}, %{})

    started_at = System.monotonic_time(:millisecond)
    %{synced_count: synced_count, skipped_count: skipped_count, stale_count: stale_count} = ship_entries(pending_rows)

    if pending_count > 0 do
      Logger.info(
        "Distributed KV shipper synced #{synced_count} row(s) to shared store successfully (pending=#{pending_count}, stale=#{stale_count}, skipped=#{skipped_count})"
      )
    end

    :telemetry.execute(
      @telemetry_event,
      %{duration_ms: System.monotonic_time(:millisecond) - started_at, batch_size: pending_count},
      %{status: :ok}
    )

    %{batch_full?: pending_count == batch_size}
  end

  defp ship_entries([]), do: %{synced_count: 0, skipped_count: 0, stale_count: 0}

  defp ship_entries(pending_rows) do
    {prepared_rows, skipped_entries} =
      Enum.reduce(pending_rows, {[], []}, fn entry, {good, bad} ->
        case prepare_pending_row(entry) do
          {:ok, row} -> {[row | good], bad}
          :skip -> {good, [entry | bad]}
        end
      end)

    prepared_rows = Enum.reverse(prepared_rows)

    if skipped_entries != [] do
      Logger.warning("Skipped #{length(skipped_entries)} rows with malformed keys during replication")
      _ = KeyValueEntries.clear_replication_tokens(Enum.reverse(skipped_entries))
    end

    cleanup_barriers =
      prepared_rows
      |> Enum.map(& &1.scope)
      |> Cleanup.effective_project_barriers()

    {stale_rows, active_rows} =
      Enum.split_with(prepared_rows, &stale_against_cleanup?(&1, cleanup_barriers))

    Enum.each(stale_rows, &discard_stale_row/1)
    ship_batch(active_rows)

    %{
      synced_count: length(active_rows),
      skipped_count: length(skipped_entries),
      stale_count: length(stale_rows)
    }
  end

  defp prepare_pending_row(entry) do
    case KeyValueEntry.scope_from_key(entry.key) do
      {:ok, scope} ->
        incoming = %{
          key: entry.key,
          account_handle: scope.account_handle,
          project_handle: scope.project_handle,
          cas_id: scope.cas_id,
          json_payload: entry.json_payload,
          source_node: pending_source_node(entry),
          source_updated_at: entry.source_updated_at,
          last_accessed_at: entry.last_accessed_at
        }

        {:ok, %{entry: entry, scope: scope, incoming: incoming, access_only?: pending_access_bump_only?(entry)}}

      :error ->
        :skip
    end
  end

  defp pending_source_node(entry) do
    if pending_access_bump_only?(entry) do
      entry.source_node || Config.distributed_kv_node_name()
    else
      Config.distributed_kv_node_name()
    end
  end

  defp pending_access_bump_only?(%{replication_enqueued_at: nil}), do: false
  defp pending_access_bump_only?(%{source_updated_at: nil}), do: false

  defp pending_access_bump_only?(entry) do
    DateTime.after?(entry.replication_enqueued_at, entry.source_updated_at)
  end

  defp ship_batch([]), do: :ok

  defp ship_batch(rows) do
    {access_only_rows, payload_rows} = Enum.split_with(rows, & &1.access_only?)

    touched_access_keys =
      access_only_rows
      |> Enum.map(fn row ->
        %{key: row.incoming.key, last_accessed_at: row.incoming.last_accessed_at}
      end)
      |> touch_shared_entries()

    fallback_payload_rows =
      Enum.reject(access_only_rows, fn row ->
        MapSet.member?(touched_access_keys, row.entry.key)
      end)

    rows_to_upsert = payload_rows ++ fallback_payload_rows
    upsert_shared_entries(Enum.map(rows_to_upsert, & &1.incoming))

    successfully_shipped_entries =
      access_only_rows
      |> Enum.filter(fn row -> MapSet.member?(touched_access_keys, row.entry.key) end)
      |> Enum.map(& &1.entry)
      |> Kernel.++(Enum.map(rows_to_upsert, & &1.entry))

    _ = KeyValueEntries.clear_replication_tokens(successfully_shipped_entries)

    :ok
  end

  defp touch_shared_entries([]), do: MapSet.new()

  defp touch_shared_entries(rows) do
    query =
      from(entry in Entry,
        join: row in values(rows, @shared_touch_types),
        on: entry.key == row.key,
        update: [
          set: [
            last_accessed_at: fragment("GREATEST(?, ?)", entry.last_accessed_at, row.last_accessed_at),
            updated_at: fragment("clock_timestamp()::timestamp")
          ]
        ],
        select: entry.key
      )

    {_count, keys} =
      Repo.update_all(query, [], timeout: Config.distributed_kv_database_timeout_ms())

    MapSet.new(keys)
  end

  @doc false
  def upsert_shared_entries(rows)

  def upsert_shared_entries([]), do: :ok

  def upsert_shared_entries(rows) do
    insert_query =
      from(row in values(rows, @shared_insert_types),
        select: %{
          key: row.key,
          account_handle: row.account_handle,
          project_handle: row.project_handle,
          cas_id: row.cas_id,
          json_payload: row.json_payload,
          source_node: row.source_node,
          source_updated_at: row.source_updated_at,
          last_accessed_at: row.last_accessed_at,
          updated_at: fragment("clock_timestamp()::timestamp")
        }
      )

    # Shared rows resolve payload conflicts by source_updated_at, then source_node for equal timestamps.
    on_conflict =
      from(entry in Entry,
        update: [
          set: [
            account_handle: fragment("EXCLUDED.account_handle"),
            project_handle: fragment("EXCLUDED.project_handle"),
            cas_id: fragment("EXCLUDED.cas_id"),
            json_payload:
              fragment(
                "CASE WHEN EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?) THEN EXCLUDED.json_payload ELSE ? END",
                entry.source_updated_at,
                entry.source_updated_at,
                entry.source_node,
                entry.json_payload
              ),
            source_node:
              fragment(
                "CASE WHEN EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?) THEN EXCLUDED.source_node ELSE ? END",
                entry.source_updated_at,
                entry.source_updated_at,
                entry.source_node,
                entry.source_node
              ),
            source_updated_at:
              fragment(
                "CASE WHEN EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?) THEN EXCLUDED.source_updated_at ELSE ? END",
                entry.source_updated_at,
                entry.source_updated_at,
                entry.source_node,
                entry.source_updated_at
              ),
            last_accessed_at: fragment("GREATEST(?, EXCLUDED.last_accessed_at)", entry.last_accessed_at),
            deleted_at:
              fragment(
                "CASE WHEN (EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?)) AND ? IS NOT NULL AND EXCLUDED.source_updated_at > ? THEN NULL ELSE ? END",
                entry.source_updated_at,
                entry.source_updated_at,
                entry.source_node,
                entry.deleted_at,
                entry.deleted_at,
                entry.deleted_at
              ),
            updated_at: fragment("clock_timestamp()::timestamp")
          ]
        ]
      )

    Repo.insert_all(Entry, insert_query,
      on_conflict: on_conflict,
      conflict_target: :key,
      timeout: Config.distributed_kv_database_timeout_ms()
    )

    :ok
  end

  defp discard_stale_row(row) do
    _ = KeyValueEntries.delete_local_entry_if_before_or_equal(row.entry.key, row.entry.source_updated_at)
    _ = KeyValueEntries.clear_replication_token(row.entry.key, row.entry.replication_enqueued_at)
    KeyValueAccessTracker.clear(row.entry.key)
    {:ok, _} = Cachex.del(KeyValueStore.cache_name(), row.entry.key)
    :ok
  end

  defp stale_against_cleanup?(row, cleanup_barriers) do
    case Map.get(cleanup_barriers, {row.scope.account_handle, row.scope.project_handle}) do
      nil ->
        false

      barrier ->
        DateTime.compare(row.entry.source_updated_at, barrier) in [:lt, :eq]
    end
  end

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :flush, interval_ms)
  end
end
