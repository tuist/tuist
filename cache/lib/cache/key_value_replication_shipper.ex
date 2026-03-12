defmodule Cache.KeyValueReplicationShipper do
  @moduledoc false

  use GenServer

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
        Enum.each(pending_rows, &ship_entry/1)
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

  defp ship_entry(entry) do
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

    if stale_against_cleanup?(entry, scope) do
      _ = KeyValueEntries.delete_local_entry_if_before_or_equal(entry.key, entry.source_updated_at)
      _ = KeyValueEntries.clear_replication_token(entry.key, entry.replication_enqueued_at)
      KeyValueAccessTracker.clear(entry.key)
      Cachex.del(:cache_keyvalue_store, entry.key)
      :ok
    else
      do_ship_entry(entry, incoming)
    end
  end

  defp do_ship_entry(entry, incoming) do
    now = DateTime.utc_now()

    DistributedRepo.transaction(
      fn ->
        case DistributedRepo.get(DistributedEntry, entry.key) do
          nil ->
            %DistributedEntry{}
            |> DistributedEntry.changeset(Map.put(incoming, :updated_at, now))
            |> DistributedRepo.insert!()

          existing ->
            merged = Logic.merge_shared_entry(existing, incoming, now)

            existing
            |> DistributedEntry.changeset(merged)
            |> DistributedRepo.update!()
        end
      end,
      timeout: Config.distributed_kv_database_timeout_ms()
    )

    _ = KeyValueEntries.clear_replication_token(entry.key, entry.replication_enqueued_at)
    :ok
  end

  defp stale_against_cleanup?(entry, scope) do
    case Cleanup.latest_project_cleanup_cutoff(scope.account_handle, scope.project_handle) do
      nil -> false
      cleanup_started_at -> DateTime.compare(entry.source_updated_at, cleanup_started_at) in [:lt, :eq]
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
