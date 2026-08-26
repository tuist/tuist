defmodule Tuist.Kura.StorageTelemetry do
  @moduledoc """
  Persists and queries the storage telemetry Kura nodes attach to their usage
  batches: evictions shed under ring size pressure, and ring-occupancy
  snapshots. The inputs of claim sizing.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Kura.EvictionEvent
  alias Tuist.Kura.StorageSnapshot

  @max_events_per_batch 5_000

  def create_eviction_events(events) when is_list(events) and length(events) <= @max_events_per_batch do
    insert_rows(EvictionEvent, events, &eviction_row/3)
  end

  def create_eviction_events(events) when is_list(events), do: {:error, :too_many_events}

  def create_storage_snapshots(events) when is_list(events) and length(events) <= @max_events_per_batch do
    insert_rows(StorageSnapshot, events, &snapshot_row/3)
  end

  def create_storage_snapshots(events) when is_list(events), do: {:error, :too_many_events}

  defp insert_rows(schema, events, row_builder) do
    account_ids_by_handle = lookup_account_ids(events)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    rows = Enum.map(events, &row_builder.(&1, account_ids_by_handle, now))

    if rows != [] do
      IngestRepo.insert_all(schema, rows)
    end

    {:ok, length(rows)}
  end

  # Unresolvable tenants drop to 0, matching `Tuist.Kura.Usage`.
  defp lookup_account_ids(events) do
    events
    |> Enum.map(& &1["tenant_id"])
    |> Accounts.get_account_ids_by_handles()
  end

  defp eviction_row(event, account_ids_by_handle, now) do
    %{
      event_id: event["event_id"],
      account_id: resolve_account_id(account_ids_by_handle, event["tenant_id"]),
      node_id: event["node_id"],
      region: event["region"],
      segment_id: event["segment_id"],
      reason: event["reason"],
      evicted_at: unix_ms_to_naive_datetime(event["evicted_at_unix_ms"]),
      segment_created_at: unix_ms_to_naive_datetime(event["segment_created_at_unix_ms"]),
      newest_content_at: unix_ms_to_naive_datetime(event["newest_content_at_unix_ms"]),
      artifact_count: event["artifact_count"],
      bytes: event["bytes"],
      inserted_at: now
    }
  end

  defp snapshot_row(event, account_ids_by_handle, now) do
    %{
      event_id: event["event_id"],
      account_id: resolve_account_id(account_ids_by_handle, event["tenant_id"]),
      node_id: event["node_id"],
      region: event["region"],
      captured_at: unix_ms_to_naive_datetime(event["captured_at_unix_ms"]),
      ring_budget_bytes: event["ring_budget_bytes"],
      desired_segment_count: event["desired_segment_count"],
      live_segment_count: event["live_segment_count"],
      live_segment_bytes: event["live_segment_bytes"],
      oldest_segment_created_at: unix_ms_to_naive_datetime(event["oldest_segment_created_at_unix_ms"]),
      newest_content_at: unix_ms_to_naive_datetime(event["newest_content_at_unix_ms"]),
      inserted_at: now
    }
  end

  defp resolve_account_id(account_ids_by_handle, tenant_id) do
    Map.get(account_ids_by_handle, tenant_id) || 0
  end

  # Absent timestamps land as the epoch; readers gate on live_segment_count.
  defp unix_ms_to_naive_datetime(nil), do: ~N[1970-01-01 00:00:00]

  defp unix_ms_to_naive_datetime(ms) when is_integer(ms) do
    ms
    |> div(1_000)
    |> DateTime.from_unix!()
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  @doc """
  Per-day eviction aggregates for every account-region with capacity
  evictions in `[start_date, end_date]`, deduplicated by event id.

  `min_shed_age_seconds` / `median_shed_age_seconds` measure
  `evicted_at - newest_content_at`: how soon after being written the youngest
  artifact in an evicted segment was shed. `median_ring_span_seconds` measures
  `evicted_at - segment_created_at`: how much history the ring held when it
  rotated, the value claim growth is projected from.
  """
  def eviction_day_aggregates(start_date, end_date) do
    start_naive = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_naive = NaiveDateTime.new!(end_date, ~T[23:59:59])

    deduped =
      from(e in EvictionEvent,
        where: e.evicted_at >= ^start_naive and e.evicted_at <= ^end_naive,
        where: e.account_id > 0 and e.reason == "capacity",
        group_by: e.event_id,
        select: %{
          account_id: fragment("argMax(?, ?)", e.account_id, e.inserted_at),
          region: fragment("argMax(?, ?)", e.region, e.inserted_at),
          evicted_at: fragment("argMax(?, ?)", e.evicted_at, e.inserted_at),
          segment_created_at: fragment("argMax(?, ?)", e.segment_created_at, e.inserted_at),
          newest_content_at: fragment("argMax(?, ?)", e.newest_content_at, e.inserted_at),
          artifact_count: fragment("argMax(?, ?)", e.artifact_count, e.inserted_at),
          bytes: fragment("argMax(?, ?)", e.bytes, e.inserted_at)
        }
      )

    ClickHouseRepo.all(
      from(e in subquery(deduped),
        group_by: [e.account_id, e.region, fragment("toDate(?)", e.evicted_at)],
        select: %{
          account_id: e.account_id,
          region: e.region,
          date: fragment("toDate(?)", e.evicted_at),
          eviction_count: fragment("toUInt64(count())"),
          evicted_bytes: fragment("sum(?)", e.bytes),
          evicted_artifact_count: fragment("sum(?)", e.artifact_count),
          min_shed_age_seconds: fragment("min(dateDiff('second', ?, ?))", e.newest_content_at, e.evicted_at),
          median_shed_age_seconds:
            fragment(
              "toInt64(quantileExact(0.5)(dateDiff('second', ?, ?)))",
              e.newest_content_at,
              e.evicted_at
            ),
          median_ring_span_seconds:
            fragment(
              "toInt64(quantileExact(0.5)(dateDiff('second', ?, ?)))",
              e.segment_created_at,
              e.evicted_at
            )
        }
      )
    )
  end

  @doc """
  The latest snapshot per (region, node) for one account within the trailing
  week: what each Kura pod's disk actually holds right now, for the ops
  account page. A pod that stopped reporting ages out of the view with its
  snapshots.
  """
  def latest_snapshots(account_id) when is_integer(account_id) do
    since =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-7 * 86_400)
      |> NaiveDateTime.truncate(:second)

    deduped =
      from(s in StorageSnapshot,
        where: s.account_id == ^account_id and s.captured_at >= ^since,
        group_by: s.event_id,
        select: %{
          region: fragment("argMax(?, ?)", s.region, s.inserted_at),
          node_id: fragment("argMax(?, ?)", s.node_id, s.inserted_at),
          captured_at: fragment("argMax(?, ?)", s.captured_at, s.inserted_at),
          ring_budget_bytes: fragment("argMax(?, ?)", s.ring_budget_bytes, s.inserted_at),
          live_segment_bytes: fragment("argMax(?, ?)", s.live_segment_bytes, s.inserted_at),
          live_segment_count: fragment("argMax(?, ?)", s.live_segment_count, s.inserted_at)
        }
      )

    ClickHouseRepo.all(
      from(s in subquery(deduped),
        group_by: [s.region, s.node_id],
        order_by: [asc: s.region, asc: s.node_id],
        select: %{
          region: s.region,
          node_id: s.node_id,
          captured_at: fragment("max(?)", s.captured_at),
          ring_budget_bytes: fragment("argMax(?, ?)", s.ring_budget_bytes, s.captured_at),
          live_segment_bytes: fragment("argMax(?, ?)", s.live_segment_bytes, s.captured_at),
          live_segment_count: fragment("argMax(?, ?)", s.live_segment_count, s.captured_at)
        }
      )
    )
  end

  @doc """
  Per-day occupancy aggregates for every account-region with snapshots in
  `[start_date, end_date]`, deduplicated by event id.

  Occupancy compares live segment bytes to the ring budget the node resolved
  from its claim. The day's maximum is what sizing reads: shrink wants to know
  the ring never filled, grow wants to know it did.
  """
  def snapshot_day_aggregates(start_date, end_date) do
    start_naive = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_naive = NaiveDateTime.new!(end_date, ~T[23:59:59])

    deduped =
      from(s in StorageSnapshot,
        where: s.captured_at >= ^start_naive and s.captured_at <= ^end_naive,
        where: s.account_id > 0,
        group_by: s.event_id,
        select: %{
          account_id: fragment("argMax(?, ?)", s.account_id, s.inserted_at),
          region: fragment("argMax(?, ?)", s.region, s.inserted_at),
          captured_at: fragment("argMax(?, ?)", s.captured_at, s.inserted_at),
          ring_budget_bytes: fragment("argMax(?, ?)", s.ring_budget_bytes, s.inserted_at),
          live_segment_bytes: fragment("argMax(?, ?)", s.live_segment_bytes, s.inserted_at)
        }
      )

    ClickHouseRepo.all(
      from(s in subquery(deduped),
        group_by: [s.account_id, s.region, fragment("toDate(?)", s.captured_at)],
        select: %{
          account_id: s.account_id,
          region: s.region,
          date: fragment("toDate(?)", s.captured_at),
          snapshot_count: fragment("toUInt64(count())"),
          max_occupancy_percent:
            fragment(
              "toInt64(max(if(? = 0, 0, round(? * 100 / ?))))",
              s.ring_budget_bytes,
              s.live_segment_bytes,
              s.ring_budget_bytes
            ),
          max_live_segment_bytes: fragment("max(?)", s.live_segment_bytes),
          last_ring_budget_bytes: fragment("argMax(?, ?)", s.ring_budget_bytes, s.captured_at)
        }
      )
    )
  end
end
