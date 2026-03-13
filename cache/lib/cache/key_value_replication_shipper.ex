defmodule Cache.KeyValueReplicationShipper do
  @moduledoc false

  use GenServer

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Repo, as: DistributedRepo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries

  require Logger

  @telemetry_event [:cache, :kv, :replication, :ship, :flush]
  @pending_rows_event [:cache, :kv, :replication, :ship, :pending_rows]
  @timeout_event [:cache, :kv, :replication, :ship, :timeout]
  @shared_payload_wins_sql """
  EXCLUDED.source_updated_at > kv_entries.source_updated_at OR (
    EXCLUDED.source_updated_at = kv_entries.source_updated_at AND
      EXCLUDED.source_node > kv_entries.source_node
  )
  """

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
    DistributedRepo.query!(
      """
      INSERT INTO kv_entries (
        key,
        account_handle,
        project_handle,
        cas_id,
        json_payload,
        source_node,
        source_updated_at,
        last_accessed_at,
        updated_at
      )
      SELECT
        incoming.key,
        incoming.account_handle,
        incoming.project_handle,
        incoming.cas_id,
        incoming.json_payload,
        incoming.source_node,
        incoming.source_updated_at,
        incoming.last_accessed_at,
        incoming.updated_at
      FROM UNNEST(
        $1::text[],
        $2::text[],
        $3::text[],
        $4::text[],
        $5::text[],
        $6::text[],
        $7::timestamptz[],
        $8::timestamptz[],
        $9::timestamptz[]
      ) AS incoming(
        key,
        account_handle,
        project_handle,
        cas_id,
        json_payload,
        source_node,
        source_updated_at,
        last_accessed_at,
        updated_at
      )
      ON CONFLICT (key) DO UPDATE
      SET
        account_handle = EXCLUDED.account_handle,
        project_handle = EXCLUDED.project_handle,
        cas_id = EXCLUDED.cas_id,
        json_payload = CASE
          WHEN #{@shared_payload_wins_sql} THEN EXCLUDED.json_payload
          ELSE kv_entries.json_payload
        END,
        source_node = CASE
          WHEN #{@shared_payload_wins_sql} THEN EXCLUDED.source_node
          ELSE kv_entries.source_node
        END,
        source_updated_at = CASE
          WHEN #{@shared_payload_wins_sql} THEN EXCLUDED.source_updated_at
          ELSE kv_entries.source_updated_at
        END,
        last_accessed_at = GREATEST(kv_entries.last_accessed_at, EXCLUDED.last_accessed_at),
        deleted_at = CASE
          WHEN #{@shared_payload_wins_sql} AND kv_entries.deleted_at IS NOT NULL AND
                 EXCLUDED.source_updated_at > kv_entries.deleted_at THEN NULL
          ELSE kv_entries.deleted_at
        END,
        updated_at = EXCLUDED.updated_at
      """,
      upsert_shared_entry_params(rows, now),
      timeout: Config.distributed_kv_database_timeout_ms()
    )

    :ok
  end

  defp upsert_shared_entry_params(rows, now) do
    [
      Enum.map(rows, & &1.key),
      Enum.map(rows, & &1.account_handle),
      Enum.map(rows, & &1.project_handle),
      Enum.map(rows, & &1.cas_id),
      Enum.map(rows, & &1.json_payload),
      Enum.map(rows, & &1.source_node),
      Enum.map(rows, & &1.source_updated_at),
      Enum.map(rows, & &1.last_accessed_at),
      List.duplicate(now, length(rows))
    ]
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
