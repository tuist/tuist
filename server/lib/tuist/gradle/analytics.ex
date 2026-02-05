defmodule Tuist.Gradle.Analytics do
  @moduledoc """
  Analytics module for Gradle build insights.

  Provides Gradle-native metrics following Develocity conventions:
  - Cache hit rate: (LOCAL_HIT + REMOTE_HIT) / CACHEABLE for cacheable tasks
  - Avoidance rate: (LOCAL_HIT + REMOTE_HIT + UP_TO_DATE) / total_tasks
  - Task outcome breakdown
  - Cache event analytics
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.Build
  alias Tuist.Gradle.CacheEvent
  alias Tuist.Tasks

  @doc """
  Calculates the cache hit rate for a project over a time period.

  Cache hit rate = (LOCAL_HIT + REMOTE_HIT) / CACHEABLE for cacheable tasks only.

  ## Returns
    A float between 0.0 and 100.0, or 0.0 if no data.
  """
  def cache_hit_rate(project_id, start_datetime, end_datetime, _opts \\ []) do
    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^DateTime.to_naive(start_datetime) and
            b.inserted_at <= ^DateTime.to_naive(end_datetime) and
            b.cacheable_tasks_count > 0,
        select: %{
          local_hit: sum(b.tasks_local_hit_count),
          remote_hit: sum(b.tasks_remote_hit_count),
          cacheable: sum(b.cacheable_tasks_count)
        }
      )

    result = ClickHouseRepo.one(query)

    case result do
      %{local_hit: local_hit, remote_hit: remote_hit, cacheable: cacheable}
      when not is_nil(cacheable) ->
        from_cache = (local_hit || 0) + (remote_hit || 0)

        if cacheable > 0 do
          from_cache / cacheable * 100.0
        else
          0.0
        end

      _ ->
        0.0
    end
  end

  @doc """
  Calculates the avoidance rate for a project over a time period.

  Avoidance rate = (LOCAL_HIT + REMOTE_HIT + UP_TO_DATE) / total_tasks

  This represents the percentage of tasks that didn't need to execute.

  ## Returns
    A float between 0.0 and 100.0, or 0.0 if no data.
  """
  def avoidance_rate(project_id, start_datetime, end_datetime, _opts \\ []) do
    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^DateTime.to_naive(start_datetime) and
            b.inserted_at <= ^DateTime.to_naive(end_datetime),
        select: %{
          avoided:
            sum(b.tasks_local_hit_count) + sum(b.tasks_remote_hit_count) +
              sum(b.tasks_up_to_date_count),
          total:
            sum(b.tasks_local_hit_count) + sum(b.tasks_remote_hit_count) +
              sum(b.tasks_up_to_date_count) +
              sum(b.tasks_executed_count) + sum(b.tasks_failed_count) +
              sum(b.tasks_skipped_count) + sum(b.tasks_no_source_count)
        }
      )

    case ClickHouseRepo.one(query) do
      %{avoided: avoided, total: total}
      when not is_nil(avoided) and not is_nil(total) and total > 0 ->
        avoided / total * 100.0

      _ ->
        0.0
    end
  end

  @doc """
  Gets cache hit rate analytics with trend and time-series data.

  ## Returns
    A map with:
    - `:trend` - Percentage change from previous period
    - `:avg_hit_rate` - Average cache hit rate for the period
    - `:dates` - List of date strings
    - `:values` - List of hit rate values
  """
  def cache_hit_rate_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime, end_datetime)
    date_format = get_date_format(date_period)

    current_hit_rate = cache_hit_rate(project_id, start_datetime, end_datetime)

    previous_hit_rate =
      cache_hit_rate(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime
      )

    hit_rate_data = cache_hit_rates_over_time(project_id, start_datetime, end_datetime, date_format)

    processed_data = process_hit_rate_data(hit_rate_data, start_datetime, end_datetime, date_period)

    %{
      trend: trend(previous_hit_rate, current_hit_rate),
      avg_hit_rate: current_hit_rate,
      dates: Enum.map(processed_data, & &1.date),
      values: Enum.map(processed_data, & &1.hit_rate)
    }
  end

  defp cache_hit_rates_over_time(project_id, start_datetime, end_datetime, date_format) do
    query =
      from(b in Build,
        group_by: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^DateTime.to_naive(start_datetime) and
            b.inserted_at <= ^DateTime.to_naive(end_datetime) and
            b.cacheable_tasks_count > 0,
        select: %{
          date: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
          local_hit: sum(b.tasks_local_hit_count),
          remote_hit: sum(b.tasks_remote_hit_count),
          cacheable: sum(b.cacheable_tasks_count)
        },
        order_by: [asc: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format)]
      )

    query
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      cacheable = row.cacheable || 0
      from_cache = (row.local_hit || 0) + (row.remote_hit || 0)

      hit_rate =
        if cacheable > 0 do
          from_cache / cacheable * 100.0
        else
          0.0
        end

      %{date: row.date, hit_rate: hit_rate}
    end)
  end

  @doc """
  Gets cache hit rate percentile analytics.

  ## Parameters
    - `project_id` - The project ID
    - `percentile` - The percentile (0.5, 0.9, 0.99)
    - `opts` - Options including `:start_datetime`, `:end_datetime`

  ## Returns
    A map with trend, percentile hit rate, dates, and values.
  """
  def cache_hit_rate_percentile(project_id, percentile, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime, end_datetime)
    date_format = get_date_format(date_period)

    current_percentile =
      cache_hit_rate_period_percentile(project_id, percentile, start_datetime, end_datetime)

    previous_percentile =
      cache_hit_rate_period_percentile(
        project_id,
        percentile,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime
      )

    percentile_data =
      cache_hit_rate_percentiles_over_time(project_id, percentile, start_datetime, end_datetime, date_format)

    processed_data = process_hit_rate_data(percentile_data, start_datetime, end_datetime, date_period)

    %{
      trend: trend(previous_percentile, current_percentile),
      total_percentile_hit_rate: current_percentile,
      dates: Enum.map(processed_data, & &1.date),
      values: Enum.map(processed_data, & &1.hit_rate)
    }
  end

  defp cache_hit_rate_period_percentile(project_id, percentile, start_datetime, end_datetime) do
    flipped_percentile = 1.0 - percentile

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^DateTime.to_naive(start_datetime) and
            b.inserted_at <= ^DateTime.to_naive(end_datetime) and
            b.cacheable_tasks_count > 0,
        select:
          fragment(
            "quantile(?)(( ? + ? ) / ? * 100.0)",
            ^flipped_percentile,
            b.tasks_local_hit_count,
            b.tasks_remote_hit_count,
            b.cacheable_tasks_count
          )
      )

    case ClickHouseRepo.one(query) do
      nil -> 0.0
      value when is_float(value) -> value
      value -> value
    end
  end

  defp cache_hit_rate_percentiles_over_time(project_id, percentile, start_datetime, end_datetime, date_format) do
    flipped_percentile = 1.0 - percentile

    query =
      from(b in Build,
        group_by: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^DateTime.to_naive(start_datetime) and
            b.inserted_at <= ^DateTime.to_naive(end_datetime) and
            b.cacheable_tasks_count > 0,
        select: %{
          date: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
          percentile_hit_rate:
            fragment(
              "quantile(?)(( ? + ? ) / ? * 100.0)",
              ^flipped_percentile,
              b.tasks_local_hit_count,
              b.tasks_remote_hit_count,
              b.cacheable_tasks_count
            )
        },
        order_by: [asc: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format)]
      )

    query
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{date: row.date, hit_rate: row.percentile_hit_rate || 0.0}
    end)
  end

  @doc """
  Gets task outcome breakdown for a project over a time period.

  ## Returns
    A map with counts for each outcome:
    - `:local_hit` - Tasks restored from local cache
    - `:remote_hit` - Tasks restored from remote cache
    - `:up_to_date` - Tasks that were up to date
    - `:executed` - Tasks that were executed
    - `:failed` - Tasks that failed
    - `:skipped` - Tasks that were skipped
    - `:no_source` - Tasks with no source
  """
  def task_outcome_breakdown(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^DateTime.to_naive(start_datetime) and
            b.inserted_at <= ^DateTime.to_naive(end_datetime),
        select: %{
          local_hit: sum(b.tasks_local_hit_count),
          remote_hit: sum(b.tasks_remote_hit_count),
          up_to_date: sum(b.tasks_up_to_date_count),
          executed: sum(b.tasks_executed_count),
          failed: sum(b.tasks_failed_count),
          skipped: sum(b.tasks_skipped_count),
          no_source: sum(b.tasks_no_source_count)
        }
      )

    result = ClickHouseRepo.one(query)

    Map.new(result, fn {key, value} -> {key, value || 0} end)
  end

  @doc """
  Gets cache event analytics (uploads and downloads).

  ## Returns
    A map with:
    - `:uploads` - Map with total_size, count, trend, dates, values
    - `:downloads` - Map with total_size, count, trend, dates, values
  """
  def cache_event_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime, end_datetime)
    date_format = get_date_format(date_period)

    current_stats = cache_event_stats(project_id, start_datetime, end_datetime)

    previous_stats =
      cache_event_stats(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime
      )

    uploads_over_time = cache_events_over_time(project_id, "upload", start_datetime, end_datetime, date_format)
    downloads_over_time = cache_events_over_time(project_id, "download", start_datetime, end_datetime, date_format)

    processed_uploads = process_size_data(uploads_over_time, start_datetime, end_datetime, date_period)
    processed_downloads = process_size_data(downloads_over_time, start_datetime, end_datetime, date_period)

    %{
      uploads: %{
        total_size: current_stats.upload_size,
        count: current_stats.upload_count,
        trend: trend(previous_stats.upload_size, current_stats.upload_size),
        dates: Enum.map(processed_uploads, & &1.date),
        values: Enum.map(processed_uploads, & &1.size)
      },
      downloads: %{
        total_size: current_stats.download_size,
        count: current_stats.download_count,
        trend: trend(previous_stats.download_size, current_stats.download_size),
        dates: Enum.map(processed_downloads, & &1.date),
        values: Enum.map(processed_downloads, & &1.size)
      }
    }
  end

  defp cache_event_stats(project_id, start_datetime, end_datetime) do
    query =
      from(e in CacheEvent,
        where:
          e.project_id == ^project_id and
            e.inserted_at >= ^DateTime.to_naive(start_datetime) and
            e.inserted_at <= ^DateTime.to_naive(end_datetime),
        group_by: e.action,
        select: %{
          action: e.action,
          total_size: sum(e.size),
          count: count(e.id)
        }
      )

    results = ClickHouseRepo.all(query)

    upload_stats = Enum.find(results, %{total_size: 0, count: 0}, &(&1.action == "upload"))
    download_stats = Enum.find(results, %{total_size: 0, count: 0}, &(&1.action == "download"))

    %{
      upload_size: upload_stats.total_size || 0,
      upload_count: upload_stats.count || 0,
      download_size: download_stats.total_size || 0,
      download_count: download_stats.count || 0
    }
  end

  defp cache_events_over_time(project_id, action, start_datetime, end_datetime, date_format) do
    query =
      from(e in CacheEvent,
        group_by: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format),
        where:
          e.project_id == ^project_id and
            e.action == ^action and
            e.inserted_at >= ^DateTime.to_naive(start_datetime) and
            e.inserted_at <= ^DateTime.to_naive(end_datetime),
        select: %{
          date: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format),
          size: sum(e.size)
        },
        order_by: [asc: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format)]
      )

    ClickHouseRepo.all(query)
  end

  @doc """
  Runs all Gradle analytics queries in parallel.

  ## Returns
    A list of analytics results:
    [hit_rate_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50, task_breakdown, cache_events]
  """
  def combined_gradle_analytics(project_id, opts \\ []) do
    queries = [
      fn -> cache_hit_rate_analytics(project_id, opts) end,
      fn -> cache_hit_rate_percentile(project_id, 0.99, opts) end,
      fn -> cache_hit_rate_percentile(project_id, 0.9, opts) end,
      fn -> cache_hit_rate_percentile(project_id, 0.5, opts) end,
      fn -> task_outcome_breakdown(project_id, opts) end,
      fn -> cache_event_analytics(project_id, opts) end
    ]

    Tasks.parallel_tasks(queries)
  end

  defp trend(previous_value, current_value) when is_nil(previous_value) or previous_value == 0 do
    if current_value > 0, do: 100.0, else: 0.0
  end

  defp trend(previous_value, current_value) do
    (current_value - previous_value) / previous_value * 100.0
  end

  defp date_period(start_datetime, end_datetime) do
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    cond do
      days_delta <= 1 -> :hour
      days_delta >= 60 -> :month
      true -> :day
    end
  end

  defp get_date_format(:hour), do: "%Y-%m-%d %H:00:00"
  defp get_date_format(:day), do: "%Y-%m-%d"
  defp get_date_format(:month), do: "%Y-%m"

  defp process_hit_rate_data(data, start_datetime, end_datetime, date_period) do
    data_map = Map.new(data, &{&1.date, &1.hit_rate})

    start_datetime
    |> generate_date_range(end_datetime, date_period)
    |> Enum.map(fn date ->
      date_str = format_date(date, date_period)
      %{date: date, hit_rate: Map.get(data_map, date_str, 0.0)}
    end)
  end

  defp process_size_data(data, start_datetime, end_datetime, date_period) do
    data_map = Map.new(data, &{&1.date, &1.size})

    start_datetime
    |> generate_date_range(end_datetime, date_period)
    |> Enum.map(fn date ->
      date_str = format_date(date, date_period)
      %{date: date, size: Map.get(data_map, date_str, 0)}
    end)
  end

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

  defp format_date(%DateTime{} = dt, :hour) do
    hour_str = String.pad_leading(to_string(dt.hour), 2, "0")
    "#{Date.to_string(DateTime.to_date(dt))} #{hour_str}:00:00"
  end

  defp format_date(%DateTime{} = dt, :day), do: Date.to_string(DateTime.to_date(dt))
  defp format_date(%DateTime{} = dt, :month), do: "#{dt.year}-#{String.pad_leading(to_string(dt.month), 2, "0")}"
  defp format_date(%Date{} = date, :day), do: Date.to_string(date)
  defp format_date(%Date{} = date, :month), do: "#{date.year}-#{String.pad_leading(to_string(date.month), 2, "0")}"
end
