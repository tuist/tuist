defmodule Tuist.Cache.Analytics do
  @moduledoc """
  Module for cache-related analytics that combines data from both
  module cache (Events in ClickHouse) and Xcode cache (Builds in PostgreSQL).

  Since module cache tracks "targets" and Xcode cache tracks "tasks",
  we compute the average of the two hit rates rather than combining absolute numbers.
  """

  alias Tuist.CommandEvents
  alias Tuist.Runs.Analytics

  @doc """
  Gets combined cache hit rate by averaging module cache and Xcode cache hit rates.

  Returns the average hit rate as a float between 0.0 and 1.0.
  """
  def cache_hit_rate(project_id, start_datetime, end_datetime, opts) do
    event_result = CommandEvents.cache_hit_rate(project_id, start_datetime, end_datetime, opts)
    build_result = Analytics.build_cache_hit_rate(project_id, start_datetime, end_datetime, opts)

    module_hit_rate =
      calculate_hit_rate(
        event_result.local_cache_hits_count,
        event_result.remote_cache_hits_count,
        event_result.cacheable_targets_count
      )

    xcode_hit_rate =
      calculate_hit_rate(
        build_result.cacheable_task_local_hits_count,
        build_result.cacheable_task_remote_hits_count,
        build_result.cacheable_tasks_count
      )

    average_hit_rates(module_hit_rate, xcode_hit_rate)
  end

  @doc """
  Gets combined cache hit rates over time by averaging module cache and Xcode cache hit rates.

  Returns a list of maps, one for each time period, with:
  - date: The date string for the period
  - cache_hit_rate: The average hit rate for this period
  """
  def cache_hit_rates(project_id, start_datetime, end_datetime, date_period, time_bucket, opts) do
    event_results =
      CommandEvents.cache_hit_rates(project_id, start_datetime, end_datetime, date_period, time_bucket, opts)

    build_results = Analytics.build_cache_hit_rates(project_id, start_datetime, end_datetime, time_bucket, opts)

    event_map = Map.new(event_results, &{&1.date, &1})
    build_map = Map.new(build_results, &{&1.date, &1})

    all_dates = generate_date_range(start_datetime, end_datetime, date_period)

    Enum.map(all_dates, fn date ->
      lookup_key = date_to_string(date, date_period)
      event_data = Map.get(event_map, lookup_key)
      build_data = Map.get(build_map, lookup_key)

      module_hit_rate =
        if event_data do
          calculate_hit_rate(
            event_data.local_cache_target_hits,
            event_data.remote_cache_target_hits,
            event_data.cacheable_targets
          )
        end

      xcode_hit_rate =
        if build_data do
          calculate_hit_rate(
            build_data.cacheable_task_local_hits,
            build_data.cacheable_task_remote_hits,
            build_data.cacheable_tasks
          )
        end

      %{
        date: date,
        cache_hit_rate: average_hit_rates(module_hit_rate, xcode_hit_rate)
      }
    end)
  end

  defp calculate_hit_rate(local_hits, remote_hits, total) do
    local = local_hits || 0
    remote = remote_hits || 0
    cacheable = total || 0

    if cacheable == 0 do
      nil
    else
      (local + remote) / cacheable
    end
  end

  @doc """
  Gets combined cache hit rate analytics with trend and time-series data.

  Returns a map with:
  - trend: The percentage change from previous period
  - cache_hit_rate: The current cache hit rate
  - dates: List of date strings
  - values: List of cache hit rates for each date
  """
  def cache_hit_rate_analytics(opts) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)

    current_cache_hit_rate =
      cache_hit_rate(
        project_id,
        start_datetime,
        end_datetime,
        is_ci: is_ci
      )

    previous_cache_hit_rate =
      cache_hit_rate(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        is_ci: is_ci
      )

    cache_hit_rates_data =
      cache_hit_rates(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        time_bucket_to_clickhouse_interval(time_bucket),
        is_ci: is_ci
      )

    %{
      trend:
        Analytics.trend(
          previous_value: previous_cache_hit_rate,
          current_value: current_cache_hit_rate
        ),
      cache_hit_rate: current_cache_hit_rate,
      dates: Enum.map(cache_hit_rates_data, & &1.date),
      values: Enum.map(cache_hit_rates_data, & &1.cache_hit_rate)
    }
  end

  defp average_hit_rates(nil, nil), do: 0.0
  defp average_hit_rates(rate1, nil), do: rate1
  defp average_hit_rates(nil, rate2), do: rate2
  defp average_hit_rates(rate1, rate2), do: (rate1 + rate2) / 2

  defp date_period(opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    cond do
      days_delta <= 1 -> :hour
      days_delta >= 60 -> :month
      true -> :day
    end
  end

  defp time_bucket_for_date_period(date_period) do
    case date_period do
      :hour -> %Postgrex.Interval{secs: 3600}
      :day -> %Postgrex.Interval{days: 1}
      :month -> %Postgrex.Interval{months: 1}
    end
  end

  defp time_bucket_to_clickhouse_interval(%Postgrex.Interval{secs: 3600}), do: "1 hour"
  defp time_bucket_to_clickhouse_interval(%Postgrex.Interval{days: 1}), do: "1 day"
  defp time_bucket_to_clickhouse_interval(%Postgrex.Interval{months: 1}), do: "1 month"

  defp generate_date_range(start_datetime, end_datetime, :hour) do
    start_datetime = DateTime.truncate(start_datetime, :second)
    end_datetime = DateTime.truncate(end_datetime, :second)

    start_datetime
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
  end

  defp generate_date_range(start_datetime, end_datetime, :day) do
    start_date = DateTime.to_date(start_datetime)
    end_date = DateTime.to_date(end_datetime)

    start_date
    |> Date.range(end_date)
    |> Enum.to_list()
  end

  defp generate_date_range(start_datetime, end_datetime, :month) do
    start_date = DateTime.to_date(start_datetime)
    end_date = DateTime.to_date(end_datetime)

    start_date
    |> Date.beginning_of_month()
    |> Date.range(Date.beginning_of_month(end_date))
    |> Enum.filter(&(&1.day == 1))
  end

  defp date_to_string(%DateTime{} = dt, :hour) do
    Timex.format!(dt, "%Y-%m-%d %H:00", :strftime)
  end

  defp date_to_string(date, :day) do
    Timex.format!(date, "%Y-%m-%d", :strftime)
  end

  defp date_to_string(date, :month) do
    Timex.format!(date, "%Y-%m", :strftime)
  end
end
