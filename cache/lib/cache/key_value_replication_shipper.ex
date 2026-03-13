defmodule Cache.KeyValueReplicationShipper do
  @moduledoc false

  use GenServer

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry, as: DistributedEntry
  alias Cache.DistributedKV.Logic
  alias Cache.DistributedKV.Repo, as: DistributedRepo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries

  require Logger

  @telemetry_event [:cache, :kv, :replication, :ship, :flush]
  @pending_rows_event [:cache, :kv, :replication, :ship, :pending_rows]
  @timeout_event [:cache, :kv, :replication, :ship, :timeout]

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
  def init(state) do
    schedule_flush(0)
    {:ok, state}
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

    result =
      try do
        ship_entries(pending_rows)
        :ok
      rescue
        error ->
          maybe_emit_timeout(error)
          Logger.warning("Distributed KV shipper failed: #{Exception.message(error)}")
          {:error, error}
      end

    :telemetry.execute(
      @telemetry_event,
      %{duration_ms: System.monotonic_time(:millisecond) - started_at, batch_size: length(pending_rows)},
      %{status: if(result == :ok, do: :ok, else: :error)}
    )

    result
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
  end

  defp prepare_pending_row(entry) do
    scope =
      case Cache.KeyValueEntry.scope_from_key(entry.key) do
        {:ok, scope} -> scope
        :error -> raise "invalid KV key format for replication: #{entry.key}"
      end

    incoming = %{
      key: entry.key,
      account_handle: scope.account_handle,
      project_handle: scope.project_handle,
      cas_id: scope.cas_id,
      json_payload: entry.json_payload,
      source_node: Config.distributed_kv_node_name(),
      source_updated_at: entry.source_updated_at,
      last_accessed_at: entry.last_accessed_at
    }

    %{entry: entry, scope: scope, incoming: incoming}
  end

  defp ship_batch([]), do: :ok

  defp ship_batch(rows) do
    now = DateTime.utc_now()
    keys = Enum.map(rows, & &1.entry.key)

    DistributedRepo.transaction(
      fn ->
        existing_entries = fetch_existing_entries(keys)

        {insert_rows, update_rows} =
          Enum.reduce(rows, {[], []}, fn row, {insert_rows, update_rows} ->
            case Map.get(existing_entries, row.entry.key) do
              nil ->
                {[Map.put(row.incoming, :updated_at, now) | insert_rows], update_rows}

              existing ->
                merged = Logic.merge_shared_entry(existing, row.incoming, now)
                {insert_rows, [{existing, merged} | update_rows]}
            end
          end)

        if insert_rows != [] do
          DistributedRepo.insert_all(DistributedEntry, insert_rows)
        end

        Enum.each(update_rows, fn {existing, merged} ->
          existing
          |> DistributedEntry.changeset(merged)
          |> DistributedRepo.update!()
        end)
      end,
      timeout: Config.distributed_kv_database_timeout_ms()
    )

    Enum.each(rows, fn row ->
      _ = KeyValueEntries.clear_replication_token(row.entry.key, row.entry.replication_enqueued_at)
    end)

    :ok
  end

  defp fetch_existing_entries(keys) do
    DistributedEntry
    |> where([entry], entry.key in ^keys)
    |> DistributedRepo.all(timeout: Config.distributed_kv_database_timeout_ms())
    |> Map.new(fn entry -> {entry.key, entry} end)
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
      nil -> false
      cleanup_started_at -> DateTime.compare(row.entry.source_updated_at, cleanup_started_at) in [:lt, :eq]
    end
  end

  defp maybe_emit_timeout(%DBConnection.ConnectionError{} = _error) do
    :telemetry.execute(@timeout_event, %{count: 1}, %{region: System.get_env("DEPLOY_REGION") || "unknown"})
  end

  defp maybe_emit_timeout(_error), do: :ok

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :flush, interval_ms)
  end
end
