defmodule Atlas.TuistOverview do
  @moduledoc """
  Overview stats + daily series for the Atlas landing page.

  Each metric is measured through `Atlas.TuistServer`'s read-only Postgres and
  ClickHouse proxies, so Atlas never talks to the Tuist databases directly.
  A single `measure/2` call returns, per metric, the headline value for the
  selected time range, the previous-period delta, and a daily series suitable
  for a line or bar chart.

  Users / organizations / projects are all-time cumulative counts (their value
  grows over time), so their series is a per-day snapshot. Jobs and cache
  operations are event streams, so their series is a per-day count within the
  window.

  When the Tuist server is not reachable (dev, tests without a projected SA
  token) `measure/2` falls back to illustrative sample series in dev so the
  page renders with real-looking data while iterating on layout, and returns
  `{:error, :not_configured}` per metric elsewhere.
  """

  alias Atlas.Environment
  alias Atlas.TuistServer

  require Logger

  @cumulative_metrics [:users, :organizations, :projects]
  @event_metrics [:jobs, :cache_operations]
  @all_metrics @cumulative_metrics ++ @event_metrics

  @presets [
    %{id: "last-7-days", label: "Last 7 days", days: 7},
    %{id: "last-30-days", label: "Last 30 days", days: 30},
    %{id: "last-90-days", label: "Last 90 days", days: 90},
    %{id: "last-12-months", label: "Last 12 months", days: 365}
  ]

  @default_preset "last-30-days"

  # Dev-only base counts. The series is generated deterministically around
  # these so the chart is stable across reloads.
  @dev_base_totals %{
    users: 12_483,
    organizations: 947,
    projects: 6_128,
    jobs: 84_502,
    cache_operations: 42_378_915
  }

  def metrics, do: @all_metrics

  def presets, do: @presets

  def default_preset, do: @default_preset

  def preset(id) when is_binary(id), do: Enum.find(@presets, &(&1.id == id))
  def preset(_id), do: nil

  @doc """
  Fetches every overview stat + daily series for the given date window.

  `range` is `{start_date, end_date}` (inclusive, `Date` structs). The
  returned map keys every metric with either `{:ok, %{total, delta_pct,
  series}}` (series is a list of `[iso_date, value]` tuples) or
  `{:error, reason}`.
  """
  def measure(range, opts \\ [])

  def measure({%Date{} = start_date, %Date{} = end_date}, opts) do
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)
    ch_query = Keyword.get(opts, :ch_query, &TuistServer.clickhouse_query/2)
    configured_fun = Keyword.get(opts, :configured?, &TuistServer.configured?/0)

    days = date_range_days(start_date, end_date)
    previous_start = Date.add(start_date, -days)
    previous_end = Date.add(start_date, -1)

    cond do
      configured_fun.() ->
        Map.new(@all_metrics, fn metric ->
          {metric, measure_metric(metric, {start_date, end_date}, {previous_start, previous_end}, pg_query, ch_query)}
        end)

      Environment.dev?() ->
        Map.new(@all_metrics, fn metric -> {metric, sample_measure(metric, start_date, end_date)} end)

      true ->
        Map.new(@all_metrics, &{&1, {:error, :not_configured}})
    end
  end

  defp measure_metric(metric, current, previous, pg_query, _ch_query) when metric in @cumulative_metrics do
    cumulative_measure(cumulative_table(metric), current, previous, pg_query)
  end

  defp measure_metric(:jobs, current, previous, _pg_query, ch_query) do
    event_measure(:jobs, current, previous, ch_query)
  end

  defp measure_metric(:cache_operations, current, previous, pg_query, ch_query) do
    cache_operations_measure(current, previous, pg_query, ch_query)
  end

  defp cumulative_table(:users), do: "users"
  defp cumulative_table(:organizations), do: "organizations"
  defp cumulative_table(:projects), do: "projects"

  # Cumulative curve: measure the running total at each day inside the window
  # by combining an anchor `count(*) WHERE created_at < end_of_day` per bucket.
  # Postgres has no cheap window function for this over the whole history, so
  # we ask for the total and the per-day new rows, then walk the window
  # backwards to reconstruct daily snapshots.
  defp cumulative_measure(table, {start_date, end_date}, {previous_start, _previous_end}, pg_query) do
    sql = """
    SELECT
      (SELECT count(*) FROM #{table}) AS total_now,
      (SELECT count(*) FROM #{table} WHERE created_at < '#{iso(previous_start)}') AS total_before_previous,
      (SELECT count(*) FROM #{table} WHERE created_at < '#{iso(start_date)}') AS total_before_current,
      COALESCE((SELECT json_agg(row_to_json(t)) FROM (
        SELECT date_trunc('day', created_at)::date AS day, count(*) AS c
        FROM #{table}
        WHERE created_at >= '#{iso(previous_start)}' AND created_at < '#{iso(Date.add(end_date, 1))}'
        GROUP BY 1
        ORDER BY 1
      ) t), '[]') AS daily_new
    """

    with {:ok, row} <- fetch_one_row(pg_query, sql, "Tuist overview Postgres query failed") do
      total_now = to_integer(row["total_now"])
      total_before_prev = to_integer(row["total_before_previous"])
      total_before_curr = to_integer(row["total_before_current"])
      daily_new = decode_daily_new(row["daily_new"])

      current_series = walk_cumulative(total_before_curr, daily_new, start_date, end_date)

      previous_value = total_before_curr - total_before_prev

      {:ok,
       %{
         total: total_now,
         current_value: total_now,
         previous_value: total_before_prev + previous_value,
         delta_pct: delta_pct(total_now, total_before_prev + previous_value),
         series: current_series
       }}
    end
  end

  defp event_measure(metric, {start_date, end_date}, {previous_start, previous_end}, ch_query) do
    with {:ok, previous_total, _series} <- event_query(metric, previous_start, previous_end, ch_query),
         {:ok, current_total, series} <- event_query(metric, start_date, end_date, ch_query) do
      {:ok,
       %{
         total: current_total,
         current_value: current_total,
         previous_value: previous_total,
         delta_pct: delta_pct(current_total, previous_total),
         series: fill_series(series, start_date, end_date)
       }}
    end
  end

  defp event_query(:jobs, start_date, end_date, ch_query) do
    sql = """
    SELECT toDate(enqueued_at) AS day,
           uniqExact(workflow_job_id) AS c
    FROM runner_jobs
    WHERE enqueued_at >= {start_ts:DateTime} AND enqueued_at < {end_ts:DateTime}
    GROUP BY day
    ORDER BY day
    """

    run_event_query(sql, start_date, end_date, ch_query)
  end

  defp event_query(:cache_operations, start_date, end_date, ch_query) do
    sql = """
    SELECT day, sum(c) AS c FROM (
      SELECT toDate(created_at) AS day, count() AS c
      FROM reapi_cache_events
      WHERE created_at >= {start_ts:DateTime} AND created_at < {end_ts:DateTime}
      GROUP BY day
      UNION ALL
      SELECT toDate(created_at) AS day, count() AS c
      FROM gradle_cache_events
      WHERE created_at >= {start_ts:DateTime} AND created_at < {end_ts:DateTime}
      GROUP BY day
    )
    GROUP BY day
    ORDER BY day
    """

    run_event_query(sql, start_date, end_date, ch_query)
  end

  # Cache operations combine Xcode cache events (Postgres `cache_events`) with
  # Bazel REAPI and Gradle events (ClickHouse). Each source is queried in its
  # own database and the daily series are summed before the widget renders.
  defp cache_operations_measure({start_date, end_date}, {previous_start, previous_end}, pg_query, ch_query) do
    with {:ok, xcode_prev, _} <- xcode_cache_query(previous_start, previous_end, pg_query),
         {:ok, xcode_curr, xcode_curr_series} <- xcode_cache_query(start_date, end_date, pg_query),
         {:ok, ch_prev, _} <- event_query(:cache_operations, previous_start, previous_end, ch_query),
         {:ok, ch_curr, ch_curr_series} <- event_query(:cache_operations, start_date, end_date, ch_query) do
      combined_series = merge_series(xcode_curr_series, ch_curr_series)
      current_total = xcode_curr + ch_curr
      previous_total = xcode_prev + ch_prev

      {:ok,
       %{
         total: current_total,
         current_value: current_total,
         previous_value: previous_total,
         delta_pct: delta_pct(current_total, previous_total),
         series: fill_series(combined_series, start_date, end_date)
       }}
    end
  end

  defp xcode_cache_query(start_date, end_date, pg_query) do
    sql = """
    SELECT date_trunc('day', created_at)::date AS day, count(*) AS c
    FROM cache_events
    WHERE created_at >= '#{iso(start_date)}' AND created_at < '#{iso(Date.add(end_date, 1))}'
    GROUP BY 1
    ORDER BY 1
    """

    case pg_query.(sql, limit: 5000) do
      {:ok, %{"rows" => rows}} ->
        series =
          rows
          |> Enum.map(fn row -> {parse_date(row["day"]), to_integer(row["c"])} end)
          |> Enum.filter(fn {day, _c} -> match?(%Date{}, day) end)

        {:ok, Enum.reduce(series, 0, fn {_d, c}, acc -> acc + c end), series}

      {:error, reason} ->
        Logger.warning("Tuist overview Xcode cache Postgres query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp merge_series(left, right) do
    left
    |> Enum.concat(right)
    |> Enum.reduce(%{}, fn {%Date{} = day, count}, acc ->
      Map.update(acc, day, count, &(&1 + count))
    end)
    |> Enum.map(fn {day, count} -> {day, count} end)
    |> Enum.sort_by(fn {day, _} -> Date.to_erl(day) end)
  end

  defp run_event_query(sql, start_date, end_date, ch_query) do
    params = %{
      "start_ts" => "#{iso(start_date)} 00:00:00",
      "end_ts" => "#{iso(Date.add(end_date, 1))} 00:00:00"
    }

    case ch_query.(sql, params: params, limit: 5000) do
      {:ok, %{"rows" => rows}} ->
        series =
          Enum.map(rows, fn row ->
            {parse_date(row["day"]), to_integer(row["c"])}
          end)

        {:ok, Enum.reduce(series, 0, fn {_d, c}, acc -> acc + c end), series}

      {:error, reason} ->
        Logger.warning("Tuist overview ClickHouse query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_one_row(pg_query, sql, error_prefix) do
    case pg_query.(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} ->
        {:ok, row}

      {:ok, %{"rows" => []}} ->
        {:ok, %{}}

      {:error, reason} ->
        Logger.warning("#{error_prefix}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp walk_cumulative(baseline, daily_new, start_date, end_date) do
    counts_by_day = Map.new(daily_new, fn %{day: day, count: count} -> {day, count} end)

    start_date
    |> Date.range(end_date)
    |> Enum.map_reduce(baseline, fn day, running ->
      new_today = Map.get(counts_by_day, day, 0)
      value = running + new_today
      {{day, value}, value}
    end)
    |> elem(0)
  end

  defp decode_daily_new(nil), do: []
  defp decode_daily_new(list) when is_list(list), do: Enum.map(list, &decode_daily_new_row/1)

  defp decode_daily_new(binary) when is_binary(binary) do
    case JSON.decode(binary) do
      {:ok, list} when is_list(list) -> Enum.map(list, &decode_daily_new_row/1)
      _other -> []
    end
  end

  defp decode_daily_new_row(row) do
    %{day: parse_date(row["day"]), count: to_integer(row["c"])}
  end

  defp fill_series(series, start_date, end_date) do
    map = Map.new(series, fn {%Date{} = day, count} -> {day, count} end)

    start_date
    |> Date.range(end_date)
    |> Enum.map(fn day -> {day, Map.get(map, day, 0)} end)
  end

  defp date_range_days(%Date{} = start_date, %Date{} = end_date), do: Date.diff(end_date, start_date) + 1

  defp delta_pct(_current, 0), do: nil
  defp delta_pct(current, previous), do: Float.round((current - previous) / previous * 100.0, 1)

  defp iso(%Date{} = date), do: Date.to_iso8601(date)

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        date

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
          {:ok, ndt} -> NaiveDateTime.to_date(ndt)
          _other -> nil
        end
    end
  end

  defp parse_date(_other), do: nil

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> 0
    end
  end

  defp to_integer(_value), do: 0

  # Deterministic sample series so dev renders with real-looking numbers.
  # Cumulative metrics grow monotonically toward the base total; event
  # metrics vary weekly with a weekend dip.
  defp sample_measure(metric, start_date, end_date) do
    base = Map.fetch!(@dev_base_totals, metric)
    days = date_range_days(start_date, end_date)

    series =
      if metric in @cumulative_metrics do
        sample_cumulative_series(base, days, start_date)
      else
        sample_event_series(base, days, start_date)
      end

    current_value =
      if metric in @cumulative_metrics, do: base, else: Enum.reduce(series, 0, fn {_d, v}, acc -> acc + v end)

    previous_value = round(current_value / 1.12)

    {:ok,
     %{
       total: current_value,
       current_value: current_value,
       previous_value: previous_value,
       delta_pct: delta_pct(current_value, previous_value),
       series: series
     }}
  end

  defp sample_cumulative_series(base, days, start_date) do
    start_value = round(base / 1.15)
    step = (base - start_value) / max(days - 1, 1)

    for i <- 0..(days - 1) do
      {Date.add(start_date, i), round(start_value + step * i)}
    end
  end

  defp sample_event_series(base, days, start_date) do
    avg = base / days

    for i <- 0..(days - 1) do
      day = Date.add(start_date, i)
      dow = Date.day_of_week(day)
      # Weekend dip, mid-week peak.
      weight =
        cond do
          dow in [6, 7] -> 0.5
          dow in [2, 3, 4] -> 1.15
          true -> 0.95
        end

      {day, round(avg * weight)}
    end
  end
end
