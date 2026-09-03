defmodule Tuist.Kura.Origins do
  @moduledoc """
  Counts where an account's cache traffic comes from, per origin per day.

  Two signals with different jobs. **Runs** are what placement thresholds
  count: a build or test run that used the cache, attributed once at
  ingestion. **Resolutions** are cache-endpoint lookups, biased in both
  directions by the hour-long client cache and by the launch agent, so they
  only place an account that has nothing running yet — a question a biased
  signal can still answer, because being roughly where the account is beats
  the United States default it gets otherwise.

  The origin is resolved at the request boundary and the address is discarded
  there, so nothing finer than an account-origin-day counter exists anywhere
  downstream, in memory or on disk. A request the edge reported no location
  for is counted nowhere rather than counted as the default: an unattributed
  run is missing evidence, and inventing a majority out of it would place
  accounts on the strength of requests nobody could locate.

  The boundary is a hot path, so recording is an ETS counter and a periodic
  flush folds the buffer into `kura_origin_rollups`. Losing a flush window to
  a crash costs a minute of counts against thresholds measured in days.
  """
  use GenServer

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.OriginMap
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo

  @table __MODULE__
  @flush_interval to_timeout(minute: 1)

  @demand_position 2
  @run_position 3

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Counts one cache-endpoint resolution from `origin`. Safe from any request:
  one ETS counter update, and a no-op before the buffer has started.
  """
  def record_demand(account_id, origin), do: record(account_id, origin, @demand_position)

  @doc """
  The origin itself, from what the request path resolved. `nil` when it could
  not be attributed, which is what every reader other than the counter wants.
  """
  def value({:ok, origin}) when is_binary(origin), do: origin
  def value(origin) when is_binary(origin), do: origin
  def value(_unattributed), do: nil

  @doc """
  Counts one cache-using run from `origin`.
  """
  def record_run(account_id, origin), do: record(account_id, origin, @run_position)

  @doc """
  Removes all buffered ETS entries for `account_id`. Call this before deleting
  an account so the next flush does not attempt to write rows whose foreign key
  no longer exists.
  """
  def clear_account(account_id) when is_integer(account_id) do
    :ets.match_delete(@table, {{account_id, :_, :_}, :_, :_})
    :ok
  end

  @doc """
  Folds this node's buffer into the day's rollups. Called on the flush timer,
  and by the demand flush before it resolves regions, so an account's first
  request places it from its own origin rather than from the default.
  """
  def flush do
    if Environment.kura_demand_write_through_repo?(), do: {:ok, 0}, else: drain()
  end

  @doc """
  Rollups for these accounts from `since` onwards, grouped by account id.
  """
  def rollups_since(account_ids, %Date{} = since) do
    OriginRollup
    |> where([rollup], rollup.account_id in ^account_ids and rollup.date >= ^since)
    |> order_by([rollup], asc: rollup.date)
    |> Repo.all()
    |> Enum.group_by(& &1.account_id)
  end

  @doc """
  Upserts counts directly, adding to whatever the day already holds. The
  backfill and the tests write through here; the request path buffers.
  """
  def upsert_many(rows) when is_list(rows), do: upsert_all(rows)

  @doc """
  The account's traffic mix over the last `days`, one entry per origin with
  its totals and the region it maps to, busiest first.

  What an operator reads to see the evidence a placement decision was or was
  not taken on, before any proposal exists to explain it.
  """
  def traffic_mix(%Account{id: account_id}, days) do
    since = Date.add(Date.utc_today(), -(days - 1))

    OriginRollup
    |> where([rollup], rollup.account_id == ^account_id and rollup.date >= ^since)
    |> group_by([rollup], rollup.origin)
    |> select([rollup], %{
      origin: rollup.origin,
      run_count: type(sum(rollup.run_count), :integer),
      demand_count: type(sum(rollup.demand_count), :integer),
      last_seen_on: max(rollup.date)
    })
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :region, &1.origin |> OriginMap.candidates() |> hd()))
    |> Enum.sort_by(&{-&1.run_count, -&1.demand_count, &1.origin})
  end

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    interval = Keyword.get(opts, :flush_interval, @flush_interval)
    schedule_flush(interval)
    {:ok, %{flush_interval: interval}}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    drain()
    schedule_flush(state.flush_interval)
    {:noreply, state}
  end

  defp schedule_flush(interval), do: Process.send_after(self(), :flush, interval)

  defp record(account_id, {:ok, origin}, position), do: record(account_id, origin, position)

  defp record(account_id, origin, position) when is_integer(account_id) and is_binary(origin) do
    Telemetry.origin_attribution(signal(position), :ok)
    key = {account_id, origin, Date.utc_today()}

    if Environment.kura_demand_write_through_repo?() do
      upsert_all([row_for(key, counts_for(position))])
    else
      :ets.update_counter(@table, key, {position, 1}, {key, 0, 0})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  # An unattributed request is counted nowhere: see the moduledoc. It is still
  # counted as a request nobody could place, because otherwise an edge that
  # stopped reporting locations is indistinguishable from a quiet fleet.
  defp record(account_id, {:error, reason}, position) when is_integer(account_id) do
    Telemetry.origin_attribution(signal(position), reason)

    :ok
  end

  defp record(account_id, _origin, position) when is_integer(account_id) do
    Telemetry.origin_attribution(signal(position), :no_location)

    :ok
  end

  defp record(_account_id, _origin, _position), do: :ok

  defp signal(@demand_position), do: :resolution
  defp signal(@run_position), do: :run

  defp counts_for(@demand_position), do: {1, 0}
  defp counts_for(@run_position), do: {0, 1}

  # `:ets.take/2` reads and removes each key atomically, so a record racing the
  # drain either lands before the take and is persisted, or after it and
  # survives for the next flush.
  defp drain do
    @table
    |> :ets.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(&:ets.take(@table, &1))
    |> Enum.map(fn {key, demand_count, run_count} -> row_for(key, {demand_count, run_count}) end)
    |> upsert_all()
  end

  defp row_for({account_id, origin, date}, {demand_count, run_count}) do
    %{
      account_id: account_id,
      origin: origin,
      date: date,
      demand_count: demand_count,
      run_count: run_count
    }
  end

  defp upsert_all([]), do: {:ok, 0}

  defp upsert_all(rows) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(rows, fn row ->
        row
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    {count, _} =
      Repo.insert_all(OriginRollup, rows,
        conflict_target: [:account_id, :origin, :date],
        on_conflict:
          from(rollup in OriginRollup,
            update: [
              set: [
                demand_count: fragment("? + EXCLUDED.demand_count", rollup.demand_count),
                run_count: fragment("? + EXCLUDED.run_count", rollup.run_count),
                updated_at: fragment("EXCLUDED.updated_at")
              ]
            ]
          )
      )

    {:ok, count}
  end
end
