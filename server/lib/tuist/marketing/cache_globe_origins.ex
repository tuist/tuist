defmodule Tuist.Marketing.CacheGlobeOrigins do
  @moduledoc """
  Estimates public download origins from existing account-level origin evidence.

  Usage windows retain their measured volume and timing. Their geographic split
  is an estimate: an account's cache-using run mix, or its endpoint-resolution
  mix when it has no runs, over the last seven UTC dates. Only country-level,
  fleet-wide window aggregates leave this module. Missing evidence is omitted,
  never replaced by random locations or another account's mix.
  """

  alias Tuist.ClickHouseRepo
  alias Tuist.Marketing.CacheGlobeLocations
  alias Tuist.Repo

  require Logger

  @row_limit 25_000
  @public_window_limit 10_000
  @minimum_contributors 3
  @maximum_contributor_share 0.5

  def snapshot(now, region_ids) do
    with {:ok, %{rows: windows}} <- usage_windows(now, region_ids),
         {:ok, rollups} <- origin_rollups(windows, DateTime.to_date(now)) do
      allocate(windows, rollups)
    else
      {:error, _error} ->
        Logger.warning("Cache globe origin estimates unavailable")
        []
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("Cache globe origin estimates unavailable")
      []
  end

  defp usage_windows(now, region_ids) do
    ClickHouseRepo.query(
      """
      SELECT account_id, region, window_start, window_seconds, sum(request_count)
      FROM kura_usage_events FINAL
      WHERE window_start >= {since:DateTime} AND window_start < {now:DateTime}
        AND window_start + toIntervalSecond(window_seconds) <= {now:DateTime}
        AND window_seconds > 0 AND window_seconds <= 300
        AND traffic_plane = 'public' AND direction = 'egress' AND operation = 'download'
        AND region IN {regions:Array(String)}
      GROUP BY account_id, region, window_start, window_seconds
      HAVING sum(request_count) > 0
      """,
      %{
        "since" => now |> DateTime.add(-960, :second) |> DateTime.to_naive(),
        "now" => DateTime.to_naive(now),
        "regions" => region_ids
      },
      timeout: 15_000,
      settings: [
        max_execution_time: 10,
        max_threads: 2,
        max_memory_usage: 268_435_456,
        max_rows_to_read: 5_000_000,
        read_overflow_mode: "throw",
        max_result_rows: @row_limit,
        result_overflow_mode: "throw"
      ]
    )
  end

  defp origin_rollups([], _date), do: {:ok, []}

  defp origin_rollups(windows, date) do
    account_ids = windows |> Enum.map(&hd/1) |> Enum.uniq()

    # Cross-tenant marketing aggregate: IDs select evidence internally but are
    # stripped before caching. One bounded batch, not a query per account/window.
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL statement_timeout = '5000ms'")

      rows =
        Repo.query!(
          """
          SELECT account_id, origin, sum(run_count)::bigint, sum(demand_count)::bigint
          FROM kura_origin_rollups
          WHERE account_id = ANY($1) AND date >= $2 AND date <= $3
          GROUP BY account_id, origin
          LIMIT #{@row_limit + 1}
          """,
          [account_ids, Date.add(date, -6), date],
          timeout: 10_000
        ).rows

      if length(rows) > @row_limit, do: Repo.rollback(:row_limit), else: rows
    end)
  end

  @doc false
  def allocate(windows, rollups) do
    shares = rollups |> Enum.group_by(&hd/1) |> Map.new(fn {id, rows} -> {id, shares(rows)} end)

    windows
    |> Enum.reduce(%{}, fn [account_id, region, start, seconds, downloads], grouped ->
      Map.update(grouped, {account_id, region, start, seconds}, downloads, &(&1 + downloads))
    end)
    |> Enum.reduce_while(%{}, fn {{account_id, region, start, seconds}, downloads}, totals ->
      totals =
        Enum.reduce(Map.get(shares, account_id, []), totals, fn {location, share}, acc ->
          key = {location, region, start, seconds}

          estimate = downloads * share
          Map.update(acc, key, {estimate, MapSet.new([account_id]), estimate}, &add_volume(&1, account_id, estimate))
        end)

      if map_size(totals) > @public_window_limit, do: {:halt, nil}, else: {:cont, totals}
    end)
    |> public_origins()
  end

  @doc false
  def freeze(previous, candidates, now) do
    {:ok, cutoff, _offset} = DateTime.from_iso8601(now)
    previous = previous || %{version: 1, since: now, origins: []}
    earliest = max(previous.since, cutoff |> DateTime.add(-960, :second) |> DateTime.to_iso8601())
    retained = Enum.filter(previous.origins, &(&1.window_start >= earliest))
    eligible = Enum.filter(candidates, &(&1.window_start >= earliest))

    # Previously released values win even when late rows or origin-mix updates
    # revise their estimate. A lost journal starts AFTER its reset watermark,
    # never re-releasing older cells with a different value.
    origins =
      eligible
      |> Map.new(&{window_key(&1), &1})
      |> Map.merge(Map.new(retained, &{window_key(&1), &1}))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    origins = if length(origins) > @public_window_limit, do: retained, else: origins
    %{previous | origins: origins}
  end

  defp window_key(origin), do: {origin.location, origin.region, origin.window_start, origin.window_seconds}

  defp add_volume({volume, accounts, largest}, account_id, estimate) do
    accounts = if MapSet.size(accounts) < @minimum_contributors, do: MapSet.put(accounts, account_id), else: accounts
    {volume + estimate, accounts, max(largest, estimate)}
  end

  defp public_origins(nil) do
    Logger.warning("Cache globe origin estimates exceed public window limit")
    []
  end

  defp public_origins(totals) do
    totals
    |> Enum.filter(fn {_key, {downloads, accounts, largest}} ->
      MapSet.size(accounts) >= @minimum_contributors and largest <= downloads * @maximum_contributor_share
    end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {{location, region, start, seconds}, {downloads, _accounts, _largest}} ->
      %{
        location: location,
        region: region,
        window_start: NaiveDateTime.to_iso8601(start) <> "Z",
        window_seconds: seconds,
        # Four minutes after the window closes covers the 60s flush, delivery
        # and ingest, minute cron, bounded queries, and 30s web poll, plus margin.
        playback_delay_seconds: max(300, seconds + 240),
        downloads: downloads
      }
    end)
  end

  defp shares(rows) do
    # Runs and resolutions are different signals. Resolutions only stand in
    # when this account has no run evidence; they never outweigh known runs.
    index = if Enum.any?(rows, &(Enum.at(&1, 2) > 0)), do: 2, else: 3
    total = Enum.sum(Enum.map(rows, &Enum.at(&1, index)))

    if total > 0 do
      rows
      |> Enum.reduce(%{}, fn row, shares ->
        count = Enum.at(row, index)
        location = CacheGlobeLocations.location(Enum.at(row, 1))

        if count > 0 and location != nil,
          do: Map.update(shares, location, count / total, &(&1 + count / total)),
          else: shares
      end)
      |> Enum.to_list()
    else
      []
    end
  end
end
