defmodule Tuist.Kura.StorageRollups do
  @moduledoc """
  Maintains the day-grain Postgres rollups claim sizing reads, from the raw
  ClickHouse telemetry Kura nodes deliver. The sweep refreshes a trailing
  range every run, so today's row converges as the day accumulates and a
  late-delivered batch (nodes retry with at-least-once semantics) lands on
  the next refresh.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura.StorageRollup
  alias Tuist.Kura.StorageTelemetry
  alias Tuist.Repo

  @replace_columns [
    :eviction_count,
    :evicted_bytes,
    :evicted_artifact_count,
    :min_shed_age_seconds,
    :median_shed_age_seconds,
    :median_ring_span_seconds,
    :snapshot_count,
    :max_occupancy_percent,
    :max_live_segment_bytes,
    :last_ring_budget_bytes,
    :updated_at
  ]

  @doc """
  Recomputes the rollup rows for `[start_date, end_date]` from ClickHouse and
  upserts them. Rows for accounts that no longer exist are dropped rather
  than inserted; a deleted account has nothing left to size.
  """
  def refresh(start_date, end_date) do
    evictions = StorageTelemetry.eviction_day_aggregates(start_date, end_date)
    snapshots = StorageTelemetry.snapshot_day_aggregates(start_date, end_date)

    rows = merge_aggregates(evictions, snapshots)
    rows = Enum.filter(rows, existing_account_filter(rows))

    if rows != [] do
      Repo.insert_all(StorageRollup, rows,
        conflict_target: [:account_id, :region, :date],
        on_conflict: {:replace, @replace_columns}
      )
    end

    {:ok, length(rows)}
  end

  @doc """
  The account's rollups on or after `since_date`, every region, oldest first.
  """
  def for_account(%Account{id: account_id}, since_date) do
    StorageRollup
    |> where([rollup], rollup.account_id == ^account_id and rollup.date >= ^since_date)
    |> order_by([rollup], asc: rollup.date)
    |> Repo.all()
  end

  # Every row carries the full column set (insert_all needs homogeneous
  # keys): a day with only evictions has nil snapshot columns and vice versa,
  # which is exactly the shape the policy reads.
  defp merge_aggregates(evictions, snapshots) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    eviction_rows =
      Map.new(evictions, fn aggregate ->
        {row_key(aggregate),
         aggregate
         |> empty_row(now)
         |> Map.merge(%{
           eviction_count: aggregate.eviction_count,
           evicted_bytes: aggregate.evicted_bytes,
           evicted_artifact_count: aggregate.evicted_artifact_count,
           min_shed_age_seconds: aggregate.min_shed_age_seconds,
           median_shed_age_seconds: aggregate.median_shed_age_seconds,
           median_ring_span_seconds: aggregate.median_ring_span_seconds
         })}
      end)

    snapshots
    |> Enum.reduce(eviction_rows, fn aggregate, rows ->
      base = Map.get(rows, row_key(aggregate), empty_row(aggregate, now))

      Map.put(
        rows,
        row_key(aggregate),
        Map.merge(base, %{
          snapshot_count: aggregate.snapshot_count,
          max_occupancy_percent: aggregate.max_occupancy_percent,
          max_live_segment_bytes: aggregate.max_live_segment_bytes,
          last_ring_budget_bytes: aggregate.last_ring_budget_bytes
        })
      )
    end)
    |> Map.values()
  end

  defp empty_row(aggregate, now) do
    %{
      account_id: aggregate.account_id,
      region: aggregate.region,
      date: aggregate.date,
      eviction_count: 0,
      evicted_bytes: 0,
      evicted_artifact_count: 0,
      min_shed_age_seconds: nil,
      median_shed_age_seconds: nil,
      median_ring_span_seconds: nil,
      snapshot_count: 0,
      max_occupancy_percent: nil,
      max_live_segment_bytes: nil,
      last_ring_budget_bytes: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  defp row_key(aggregate), do: {aggregate.account_id, aggregate.region, aggregate.date}

  defp existing_account_filter(rows) do
    account_ids = rows |> Enum.map(& &1.account_id) |> Enum.uniq()

    existing =
      Account
      |> where([account], account.id in ^account_ids)
      |> select([account], account.id)
      |> Repo.all()
      |> MapSet.new()

    fn row -> MapSet.member?(existing, row.account_id) end
  end
end
