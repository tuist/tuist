defmodule Atlas.TuistOverview do
  @moduledoc """
  Overview stats + daily series for the Atlas landing page.

  Each metric is measured through `Atlas.TuistServer`'s read-only Postgres and
  ClickHouse proxies, so Atlas never talks to the Tuist databases directly.
  A single `measure/2` call returns, per metric, the headline value for the
  selected time range, the previous-period delta, and a series suitable for a
  line or bar chart.

  The series is bucketed by `granularity/2`: per day for windows of up to 30
  days, per week for windows of up to six months, and per month beyond that.
  Users / organizations / projects are all-time cumulative counts (their value
  grows over time), so each bucket holds the snapshot at its last day. Jobs and
  cache operations are event streams, so each bucket holds the count of events
  within it. Active users is a distinct count: each day holds the number of
  users who ran something that day, a week or month bucket holds the average of
  its days, and the headline is the average over the window. Summing would
  double-count anyone active on more than one day. Daily series also carry a
  `trend` series: a seven-day trailing mean of the daily counts, which cancels
  the weekday/weekend cycle so the direction of travel is readable. Weekly and
  monthly buckets already average that cycle away, so they drop the trend.

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
  @distinct_metrics [:active_users]
  @all_metrics @cumulative_metrics ++ @event_metrics ++ @distinct_metrics

  @presets [
    %{id: "last-7-days", label: "Last 7 days", days: 7},
    %{id: "last-30-days", label: "Last 30 days", days: 30},
    %{id: "last-90-days", label: "Last 90 days", days: 90},
    %{id: "last-12-months", label: "Last 12 months", days: 365}
  ]

  @default_preset "last-30-days"

  # Active users swings by a factor of five between weekdays and weekends, which
  # buries the underlying direction. A trailing mean over exactly one week
  # cancels that cycle, because every point averages the same seven weekdays.
  @trend_window_days 7

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
  Returns the chart bucket size for the inclusive `start_date..end_date` window:
  `:day` for up to 30 days, `:week` for up to six calendar months and `:month`
  beyond that.
  """
  def granularity(%Date{} = start_date, %Date{} = end_date) do
    cond do
      date_range_days(start_date, end_date) <= 30 -> :day
      Date.after?(start_date, Date.shift(end_date, month: -6)) -> :week
      true -> :month
    end
  end

  @doc """
  Fetches the most recently created Tuist organizations for the sidebar table.

  Returns `{:ok, [%{name, created_at}]}`, `{:error, :not_configured}` when the
  Tuist server is not reachable outside dev, or `{:error, reason}` for a proxy
  failure. In dev a deterministic sample list is returned so the page renders
  with real-looking data.
  """
  def recent_organizations(opts \\ []) do
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)
    configured_fun = Keyword.get(opts, :configured?, &TuistServer.configured?/0)
    limit = Keyword.get(opts, :limit, 10)

    cond do
      configured_fun.() -> fetch_recent_organizations(pg_query, limit)
      Environment.dev?() -> {:ok, sample_recent_organizations(limit)}
      true -> {:error, :not_configured}
    end
  end

  defp fetch_recent_organizations(pg_query, limit) do
    sql = """
    SELECT a.name AS name, o.created_at AS created_at
    FROM organizations o
    JOIN accounts a ON a.organization_id = o.id
    ORDER BY o.created_at DESC
    LIMIT #{limit}
    """

    case pg_query.(sql, limit: limit) do
      {:ok, %{"rows" => rows}} when is_list(rows) ->
        {:ok, Enum.map(rows, &decode_recent_organization_row/1)}

      {:error, reason} ->
        Logger.warning("Tuist overview recent organizations query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp decode_recent_organization_row(row) do
    %{
      name: to_string(row["name"] || ""),
      created_at: parse_datetime(row["created_at"])
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(%NaiveDateTime{} = ndt), do: ndt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        dt

      {:error, _} ->
        case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
          {:ok, ndt} -> ndt
          _ -> nil
        end
    end
  end

  defp parse_datetime(_), do: nil

  defp sample_recent_organizations(limit) do
    names = [
      "Acme",
      "Northwind",
      "Globex",
      "Umbrella",
      "Initech",
      "Hooli",
      "Stark Industries",
      "Wayne Enterprises",
      "Wonka",
      "Pied Piper",
      "Cyberdyne",
      "Soylent"
    ]

    now = DateTime.utc_now()

    names
    |> Enum.take(limit)
    |> Enum.with_index()
    |> Enum.map(fn {name, i} ->
      %{name: name, created_at: DateTime.add(now, -i * 86_400, :second)}
    end)
  end

  @doc """
  Fetches every overview stat + daily series for the given date window.

  `range` is `{start_date, end_date}` (inclusive, `Date` structs). The
  returned map keys every metric with either `{:ok, %{total, delta_pct,
  granularity, series}}` (series is a list of `{date, value}` tuples, one per
  `granularity/2` bucket, keyed by the bucket's first day inside the window) or
  `{:error, reason}`.
  """
  def measure(range, opts \\ [])

  def measure({%Date{}, %Date{}} = range, opts) do
    Map.new(@all_metrics, &{&1, measure_metric(&1, range, opts)})
  end

  @doc """
  Measures a single overview metric for the given date window.

  Returns the same shape as one entry of `measure/2` (`{:ok, %{...}}`,
  `{:error, :not_configured}` or `{:error, reason}`), so it can back a
  per-widget `assign_async` call in the LiveView without paying for the
  slowest query up front.
  """
  def measure_metric(metric, range, opts \\ [])

  def measure_metric(metric, {%Date{} = start_date, %Date{} = end_date}, opts) when metric in @all_metrics do
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)
    ch_query = Keyword.get(opts, :ch_query, &TuistServer.clickhouse_query/2)
    configured_fun = Keyword.get(opts, :configured?, &TuistServer.configured?/0)

    days = date_range_days(start_date, end_date)
    previous_start = Date.add(start_date, -days)
    previous_end = Date.add(start_date, -1)

    measurement =
      cond do
        configured_fun.() ->
          measure_metric(metric, {start_date, end_date}, {previous_start, previous_end}, pg_query, ch_query)

        Environment.dev?() ->
          sample_measure(metric, start_date, end_date)

        true ->
          {:error, :not_configured}
      end

    group_series(measurement, metric, start_date, end_date)
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

  defp measure_metric(:active_users, current, previous, _pg_query, ch_query) do
    active_users_measure(current, previous, ch_query)
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

  # Filter on the timestamp that is both in each table's sort key AND its
  # `toYYYYMM(...)` partition column, so ClickHouse can prune partitions and
  # skip granules:
  #   * `reapi_cache_events` → `inserted_at` (sort: `operation, project_id,
  #     inserted_at`; partition: `toYYYYMM(inserted_at)`). `observed_at` is
  #     unindexed and forces a full scan — the Kura → server delay is under
  #     one minute, so day buckets are identical.
  #   * `gradle_cache_events` → `inserted_at` (sort: `action, project_id,
  #     inserted_at`; partition: `toYYYYMM(inserted_at)`). Only option.
  defp event_query(:cache_operations, start_date, end_date, ch_query) do
    sql = """
    SELECT day, sum(c) AS c FROM (
      SELECT toDate(inserted_at) AS day, count() AS c
      FROM reapi_cache_events
      WHERE inserted_at >= {start_ts:DateTime} AND inserted_at < {end_ts:DateTime}
      GROUP BY day
      UNION ALL
      SELECT toDate(inserted_at) AS day, count() AS c
      FROM gradle_cache_events
      WHERE inserted_at >= {start_ts:DateTime} AND inserted_at < {end_ts:DateTime}
      GROUP BY day
    )
    GROUP BY day
    ORDER BY day
    """

    run_event_query(sql, start_date, end_date, ch_query)
  end

  # Cache operations combine Xcode cache hits (ClickHouse `command_events`,
  # summed per invocation) with Bazel REAPI and Gradle events (also
  # ClickHouse). Each source is queried on its own and the daily series are
  # summed before the widget renders. Postgres `cache_events` is deprecated
  # (no writers), so it is intentionally not queried here.
  defp cache_operations_measure({start_date, end_date}, {previous_start, previous_end}, _pg_query, ch_query) do
    with {:ok, xcode_prev, _} <- xcode_cache_query(previous_start, previous_end, ch_query),
         {:ok, xcode_curr, xcode_curr_series} <- xcode_cache_query(start_date, end_date, ch_query),
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

  # Unlike the event metrics, the window headline can't be a sum of the daily
  # values: a user active on ten days would be counted ten times. A window-wide
  # `uniqExact` would be exact, but it can't aggregate in order the way the
  # per-day grouping can (`ran_at` is in the sort key, `toDate(ran_at)` buckets
  # stream), and it times out against the read-only proxy even over a single
  # week. So the daily series is the source of truth and the headline is its
  # average.
  defp active_users_measure({start_date, end_date}, {previous_start, previous_end}, ch_query) do
    with {:ok, _sum, previous_series} <- active_users_query(previous_start, previous_end, ch_query),
         {:ok, _sum, current_series} <- active_users_query(start_date, end_date, ch_query) do
      series = fill_series(current_series, start_date, end_date)
      previous_filled = fill_series(previous_series, previous_start, previous_end)
      current_value = average_daily(series)
      previous_value = average_daily(previous_filled)

      {:ok,
       %{
         total: current_value,
         current_value: current_value,
         previous_value: previous_value,
         delta_pct: delta_pct(current_value, previous_value),
         series: series,
         trend: trailing_mean_series(previous_filled, series, @trend_window_days)
       }}
    end
  end

  # `user_id` is nullable — CI runs carry no user — and the `uniq*` family
  # skips nulls, so those rows drop out of the count without an extra
  # predicate that would only add a scan-time filter.
  defp active_users_query(start_date, end_date, ch_query) do
    sql = """
    SELECT toDate(ran_at) AS day, uniqExact(user_id) AS c
    FROM command_events_by_ran_at
    WHERE ran_at >= {start_ts:DateTime} AND ran_at < {end_ts:DateTime}
    GROUP BY day
    ORDER BY day
    """

    run_event_query(sql, start_date, end_date, ch_query)
  end

  # The window before the current one is already fetched for the delta, so the
  # mean is defined from the very first point of the chart rather than starting
  # six days in. Nothing here looks ahead of the point it is plotted on.
  defp trailing_mean_series(previous_series, current_series, window) do
    combined = previous_series ++ current_series
    offset = length(previous_series)

    combined
    |> Enum.with_index()
    |> Enum.drop(offset)
    |> Enum.map(fn {{day, _value}, index} ->
      {day,
       combined
       |> Enum.slice(max(index - window + 1, 0)..index)
       |> average_daily()}
    end)
  end

  defp average_daily([]), do: 0

  defp average_daily(series) do
    sum = Enum.reduce(series, 0, fn {_day, value}, acc -> acc + value end)
    round(sum / length(series))
  end

  # `command_events_by_ran_at` is the ran_at-ordered materialized view of
  # `command_events`; scanning it lets ClickHouse skip granules using the
  # ran_at sort key instead of full-scanning the name-ordered base table.
  # `remote_cache_hits_count` is a non-nullable UInt32 (default:
  # `length(remote_cache_target_hits)`), which sums without a coalesce.
  defp xcode_cache_query(start_date, end_date, ch_query) do
    sql = """
    SELECT toDate(ran_at) AS day, sum(remote_cache_hits_count) AS c
    FROM command_events_by_ran_at
    WHERE ran_at >= {start_ts:DateTime} AND ran_at < {end_ts:DateTime}
    GROUP BY day
    ORDER BY day
    """

    run_event_query(sql, start_date, end_date, ch_query)
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

  defp group_series({:ok, %{series: series} = measurement}, metric, start_date, end_date) do
    granularity = granularity(start_date, end_date)

    {:ok,
     measurement
     |> Map.put(:series, bucket_series(series, granularity, metric))
     |> Map.put(:granularity, granularity)
     |> group_trend(granularity)}
  end

  defp group_series(error, _metric, _start_date, _end_date), do: error

  defp group_trend(measurement, :day), do: measurement
  defp group_trend(measurement, _granularity), do: Map.delete(measurement, :trend)

  defp bucket_series(series, :day, _metric), do: series

  # Buckets follow calendar weeks (Monday-first) and months, so a window that
  # starts mid-week or mid-month has a partial first bucket. Each bucket is
  # keyed by its first day inside the window rather than the calendar start,
  # so the chart never shows a date outside the selected range.
  defp bucket_series(series, granularity, metric) do
    series
    |> Enum.chunk_by(fn {day, _value} -> bucket_start(day, granularity) end)
    |> Enum.map(fn [{first_day, _value} | _rest] = bucket ->
      {first_day, bucket_value(bucket, metric)}
    end)
  end

  defp bucket_start(day, :week), do: Date.beginning_of_week(day)
  defp bucket_start(day, :month), do: Date.beginning_of_month(day)

  defp bucket_value(bucket, metric) when metric in @cumulative_metrics do
    {_last_day, value} = List.last(bucket)
    value
  end

  defp bucket_value(bucket, metric) when metric in @distinct_metrics, do: average_daily(bucket)

  defp bucket_value(bucket, _metric), do: Enum.reduce(bucket, 0, fn {_day, value}, acc -> acc + value end)

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
  # Cumulative metrics grow monotonically toward the base total; event metrics
  # and active users vary weekly with a weekend dip.
  defp sample_measure(:active_users, start_date, end_date) do
    days = date_range_days(start_date, end_date)
    series = sample_active_users_series(start_date, days)
    previous_series = sample_active_users_series(Date.add(start_date, -days), days)
    current_value = average_daily(series)
    previous_value = average_daily(previous_series)

    {:ok,
     %{
       total: current_value,
       current_value: current_value,
       previous_value: previous_value,
       delta_pct: delta_pct(current_value, previous_value),
       series: series,
       trend: trailing_mean_series(previous_series, series, @trend_window_days)
     }}
  end

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

  # Compounds at roughly the rate the real series has been growing, so the dev
  # chart shows a slope the smoothed line can be checked against on the short
  # presets without running away on the twelve-month one.
  @sample_active_users_daily_growth 1.0037

  defp sample_active_users_series(start_date, days) do
    for i <- 0..(days - 1) do
      day = Date.add(start_date, i)
      elapsed = Date.diff(day, ~D[2026-01-01])
      base = if Date.day_of_week(day) in [6, 7], do: 130, else: 700
      growth = :math.pow(@sample_active_users_daily_growth, elapsed)
      # `Integer.mod/2` rather than `rem/2`: the jitter has to stay positive for
      # days before the anchor, or a range far enough back — where the growth
      # factor has decayed the base to nothing — samples a negative headcount.
      {day, max(round(base * growth) + Integer.mod(elapsed, 17), 0)}
    end
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
