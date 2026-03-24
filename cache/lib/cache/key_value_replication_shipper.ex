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

  @telemetry_event [:cache, :kv, :replication, :ship, :flush]
  @pending_rows_event [:cache, :kv, :replication, :ship, :pending_rows]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def flush_now do
    GenServer.call(__MODULE__, :flush, :infinity)
  end

  @impl true
  def init(_opts) do
    schedule_flush(0)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, flush_pending_rows(), state}
  end

  @impl true
  def handle_info(:flush, state) do
    _ = flush_pending_rows()
    schedule_flush(Config.distributed_kv_ship_interval_ms())
    {:noreply, state}
  end

  defp flush_pending_rows do
    pending_rows = KeyValueEntries.list_pending_replication()
    :telemetry.execute(@pending_rows_event, %{count: length(pending_rows)}, %{})

    started_at = System.monotonic_time(:millisecond)
    :ok = ship_entries(pending_rows)

    :telemetry.execute(
      @telemetry_event,
      %{duration_ms: System.monotonic_time(:millisecond) - started_at, batch_size: length(pending_rows)},
      %{status: :ok}
    )

    :ok
  end

  defp ship_entries([]), do: :ok

  defp ship_entries(pending_rows) do
    prepared_rows = Enum.map(pending_rows, &prepare_pending_row/1)

    cleanup_cutoffs =
      prepared_rows
      |> Enum.map(& &1.scope)
      |> Cleanup.latest_project_cleanup_cutoffs()

    {stale_rows, active_rows} =
      Enum.split_with(prepared_rows, &stale_against_cleanup?(&1, cleanup_cutoffs))

    Enum.each(stale_rows, &discard_stale_row/1)
    ship_batch(active_rows)
    :ok
  end

  defp prepare_pending_row(entry) do
    scope = Cache.KeyValueEntry.scope_from_key(entry.key)

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

    %{entry: entry, scope: scope, incoming: incoming}
  end

  defp pending_source_node(entry) do
    if access_only_pending_row?(entry) do
      entry.source_node
    else
      Config.distributed_kv_node_name()
    end
  end

  defp access_only_pending_row?(%{replication_enqueued_at: nil}), do: false
  defp access_only_pending_row?(%{source_updated_at: nil}), do: false

  defp access_only_pending_row?(entry) do
    DateTime.after?(entry.replication_enqueued_at, entry.source_updated_at)
  end

  defp ship_batch([]), do: :ok

  defp ship_batch(rows) do
    now = DateTime.utc_now()
    upsert_shared_entries(Enum.map(rows, & &1.incoming), now)

    Enum.each(rows, fn row ->
      _ = KeyValueEntries.clear_replication_token(row.entry.key, row.entry.replication_enqueued_at)
    end)

    :ok
  end

  @doc false
  def upsert_shared_entries(rows, now \\ DateTime.utc_now())

  def upsert_shared_entries([], _now), do: :ok

  def upsert_shared_entries(rows, now) do
    insert_rows =
      Enum.map(rows, fn row ->
        %{
          key: row.key,
          account_handle: row.account_handle,
          project_handle: row.project_handle,
          cas_id: row.cas_id,
          json_payload: row.json_payload,
          source_node: row.source_node,
          source_updated_at: row.source_updated_at,
          last_accessed_at: row.last_accessed_at,
          updated_at: now
        }
      end)

    # Shared rows resolve payload conflicts by source_updated_at, then source_node for equal timestamps.
    on_conflict =
      from(e in Entry,
        update: [
          set: [
            account_handle: fragment("EXCLUDED.account_handle"),
            project_handle: fragment("EXCLUDED.project_handle"),
            cas_id: fragment("EXCLUDED.cas_id"),
            json_payload:
              fragment(
                "CASE WHEN EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?) THEN EXCLUDED.json_payload ELSE ? END",
                e.source_updated_at,
                e.source_updated_at,
                e.source_node,
                e.json_payload
              ),
            source_node:
              fragment(
                "CASE WHEN EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?) THEN EXCLUDED.source_node ELSE ? END",
                e.source_updated_at,
                e.source_updated_at,
                e.source_node,
                e.source_node
              ),
            source_updated_at:
              fragment(
                "CASE WHEN EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?) THEN EXCLUDED.source_updated_at ELSE ? END",
                e.source_updated_at,
                e.source_updated_at,
                e.source_node,
                e.source_updated_at
              ),
            last_accessed_at: fragment("GREATEST(?, EXCLUDED.last_accessed_at)", e.last_accessed_at),
            deleted_at:
              fragment(
                "CASE WHEN (EXCLUDED.source_updated_at > ? OR (EXCLUDED.source_updated_at = ? AND EXCLUDED.source_node > ?)) AND ? IS NOT NULL AND EXCLUDED.source_updated_at > ? THEN NULL ELSE ? END",
                e.source_updated_at,
                e.source_updated_at,
                e.source_node,
                e.deleted_at,
                e.deleted_at,
                e.deleted_at
              ),
            updated_at: fragment("EXCLUDED.updated_at")
          ]
        ]
      )

    Repo.insert_all(Entry, insert_rows,
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
    Cachex.del(:cache_keyvalue_store, row.entry.key)
    :ok
  end

  defp stale_against_cleanup?(row, cleanup_cutoffs) do
    case Map.get(cleanup_cutoffs, {row.scope.account_handle, row.scope.project_handle}) do
      nil ->
        false

      cleanup_started_at ->
        DateTime.compare(row.entry.source_updated_at, DateTime.truncate(cleanup_started_at, :second)) in [:lt, :eq]
    end
  end

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :flush, interval_ms)
  end
end
