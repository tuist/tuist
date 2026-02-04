defmodule Tuist.Builds.Analytics do
  @moduledoc """
  Module for build-related analytics.
  """
  import Ecto.Query
  import Timescale.Hyperfunctions

  alias Postgrex.Interval
  alias Tuist.Builds.Build
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.Repo
  alias Tuist.Tasks
  alias Tuist.Xcode.XcodeGraph

  def build_duration_analytics_by_category(project_id, category, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    query =
      where(
        from(b in Build),
        [b],
        b.inserted_at > ^start_datetime and
          b.inserted_at < ^end_datetime and b.project_id == ^project_id
      )

    query =
      case category do
        :xcode_version ->
          query
          |> group_by([b], b.xcode_version)
          |> select([b], %{category: b.xcode_version, value: avg(b.duration)})

        :model_identifier ->
          query
          |> group_by([b], b.model_identifier)
          |> select([b], %{category: b.model_identifier, value: avg(b.duration)})

        :macos_version ->
          query
          |> group_by([b], b.macos_version)
          |> select([b], %{category: b.macos_version, value: avg(b.duration)})
      end

    query
    |> Repo.all()
    |> Enum.map(
      &%{
        category: &1.category,
        value:
          case &1.value do
            nil -> 0
            duration when is_float(duration) -> duration
            duration -> Decimal.to_float(duration)
          end
      }
    )
  end

  def build_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)

    current_build_data =
      build_count(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        time_bucket,
        opts
      )

    previous_builds_count =
      build_total_count(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, opts)

    current_builds_count = build_total_count(project_id, start_datetime, end_datetime, opts)

    %{
      trend:
        trend(
          previous_value: previous_builds_count,
          current_value: current_builds_count
        ),
      count: current_builds_count,
      values: Enum.map(current_build_data, & &1.count),
      dates: Enum.map(current_build_data, & &1.date)
    }
  end

  defp build_count(project_id, start_datetime, end_datetime, date_period, time_bucket, opts) do
    builds_data =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime and
            b.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
          count: count(b)
        }
      )
      |> add_filters(opts)
      |> Repo.all()
      |> Map.new(&{normalise_date(&1.date, date_period), &1.count})

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      count = Map.get(builds_data, normalized_date, 0)
      %{date: date, count: count}
    end)
  end

  defp build_total_count(project_id, start_datetime, end_datetime, opts) do
    from(b in Build,
      where:
        b.inserted_at > ^start_datetime and
          b.inserted_at < ^end_datetime and
          b.project_id == ^project_id,
      select: count(b)
    )
    |> add_filters(opts)
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  def build_duration_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)

    previous_period_data =
      build_aggregated_analytics(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, opts)

    previous_period_total_average_duration = previous_period_data.average_duration

    current_period_data = build_aggregated_analytics(project_id, start_datetime, end_datetime, opts)
    current_period_total_average_duration = current_period_data.average_duration

    average_durations_query =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime and
            b.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
          value: avg(b.duration)
        }
      )
      |> add_filters(opts)
      |> Repo.all()

    average_durations =
      process_durations_data(average_durations_query, start_datetime, end_datetime, date_period)

    %{
      trend:
        trend(
          previous_value: previous_period_total_average_duration,
          current_value: current_period_total_average_duration
        ),
      total_average_duration: current_period_total_average_duration,
      average_durations: average_durations,
      dates: Enum.map(average_durations, & &1.date),
      values: Enum.map(average_durations, & &1.value)
    }
  end

  defp build_aggregated_analytics(project_id, start_datetime, end_datetime, opts) do
    result =
      from(b in Build,
        where:
          b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime and
            b.project_id == ^project_id,
        select: %{
          total_duration: sum(b.duration),
          count: count(b),
          average_duration: avg(b.duration)
        }
      )
      |> add_filters(opts)
      |> Repo.one()

    case result do
      nil ->
        %{total_duration: 0, count: 0, average_duration: 0}

      %{total_duration: nil, count: count, average_duration: nil} ->
        %{total_duration: 0, count: count, average_duration: 0}

      %{total_duration: total, count: count, average_duration: avg} ->
        %{
          total_duration: normalize_result(total),
          count: count,
          average_duration: normalize_result(avg)
        }
    end
  end

  def build_percentile_durations(project_id, percentile, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)

    current_period_percentile =
      build_period_percentile(project_id, percentile, start_datetime, end_datetime, opts)

    previous_period_percentile =
      build_period_percentile(
        project_id,
        percentile,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        opts
      )

    durations_data =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime and
            b.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
          value: fragment("percentile_cont(?) within group (order by ?)", ^percentile, b.duration)
        }
      )
      |> add_filters(opts)
      |> Repo.all()

    durations = process_durations_data(durations_data, start_datetime, end_datetime, date_period)

    %{
      trend:
        trend(
          previous_value: previous_period_percentile,
          current_value: current_period_percentile
        ),
      total_percentile_duration: current_period_percentile,
      dates: Enum.map(durations, & &1.date),
      values: Enum.map(durations, & &1.value)
    }
  end

  defp build_period_percentile(project_id, percentile, start_datetime, end_datetime, opts) do
    result =
      from(b in Build,
        where:
          b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime and
            b.project_id == ^project_id,
        select: fragment("percentile_cont(?) within group (order by ?)", ^percentile, b.duration)
      )
      |> add_filters(opts)
      |> Repo.one()

    normalize_result(result)
  end

  def build_success_rate_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    current_success_rate =
      build_success_rate(
        project_id,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        opts: opts
      )

    previous_success_rate =
      build_success_rate(
        project_id,
        start_datetime: DateTime.add(start_datetime, -days_delta, :day),
        end_datetime: start_datetime,
        opts: opts
      )

    success_rates =
      build_success_rates_per_period(project_id,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        date_period: date_period,
        opts: opts
      )

    %{
      trend:
        trend(
          previous_value: previous_success_rate,
          current_value: current_success_rate
        ),
      success_rate: current_success_rate,
      dates:
        Enum.map(
          success_rates,
          & &1.date
        ),
      values:
        Enum.map(
          success_rates,
          & &1.success_rate
        )
    }
  end

  defp build_success_rate(project_id, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    filter_opts = Keyword.get(opts, :opts, [])

    result =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime,
        select: %{
          total_builds: count(b),
          successful_builds: fragment("COUNT(CASE WHEN ? = 0 THEN 1 END)", b.status)
        }
      )
      |> add_filters(filter_opts)
      |> Repo.one()

    total_builds = result.total_builds
    successful_builds = result.successful_builds

    if total_builds == 0 do
      0.0
    else
      successful_builds / total_builds
    end
  end

  defp build_success_rates_per_period(project_id, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    date_period = Keyword.get(opts, :date_period)
    filter_opts = Keyword.get(opts, :opts, [])

    time_bucket = time_bucket_for_date_period(date_period)

    success_rate_metadata_map =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^start_datetime and
            b.inserted_at < ^end_datetime and
            b.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
          total_builds: count(b),
          successful_builds: fragment("COUNT(CASE WHEN ? = 0 THEN 1 END)", b.status)
        }
      )
      |> add_filters(filter_opts)
      |> Repo.all()
      |> Map.new(
        &{normalise_date(&1.date, date_period),
         %{
           total_builds: &1.total_builds,
           successful_builds: &1.successful_builds
         }}
      )

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      success_rate_metadata = Map.get(success_rate_metadata_map, normalized_date)

      if is_nil(success_rate_metadata) or success_rate_metadata.total_builds == 0 do
        %{
          date: date,
          success_rate: 0.0
        }
      else
        total_builds = success_rate_metadata.total_builds
        successful_builds = success_rate_metadata.successful_builds

        %{
          date: date,
          success_rate: successful_builds / total_builds
        }
      end
    end)
  end

  def cache_hit_rate_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    current_cache_hit_rate =
      cache_hit_rate(
        project_id,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        is_ci: is_ci
      )

    previous_cache_hit_rate =
      cache_hit_rate(
        project_id,
        start_datetime: DateTime.add(start_datetime, -days_delta, :day),
        end_datetime: start_datetime,
        is_ci: is_ci
      )

    cache_hit_rates =
      cache_hit_rates(project_id,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        date_period: date_period,
        is_ci: is_ci
      )

    %{
      trend:
        trend(
          previous_value: previous_cache_hit_rate,
          current_value: current_cache_hit_rate
        ),
      cache_hit_rate: current_cache_hit_rate,
      dates:
        Enum.map(
          cache_hit_rates,
          & &1.date
        ),
      values:
        Enum.map(
          cache_hit_rates,
          & &1.cache_hit_rate
        )
    }
  end

  defp cache_hit_rate(project_id, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = DateTime.utc_now()

    result = build_cache_hit_rate(project_id, start_datetime, end_datetime, opts)

    local_cache_hits_count = result.cacheable_task_local_hits_count || 0
    remote_cache_hits_count = result.cacheable_task_remote_hits_count || 0
    cacheable_tasks_count = result.cacheable_tasks_count || 0

    if cacheable_tasks_count == 0 do
      0.0
    else
      (local_cache_hits_count + remote_cache_hits_count) / cacheable_tasks_count
    end
  end

  defp cache_hit_rates(project_id, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    cache_hit_rate_metadata_map =
      project_id
      |> build_cache_hit_rates(
        start_datetime,
        end_datetime,
        clickhouse_time_bucket,
        opts
      )
      |> Map.new(
        &{normalise_date(&1.date, date_period),
         %{
           cacheable_tasks: &1.cacheable_tasks,
           cacheable_task_local_hits: &1.cacheable_task_local_hits,
           cacheable_task_remote_hits: &1.cacheable_task_remote_hits
         }}
      )

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      cache_hit_rate_metadata = Map.get(cache_hit_rate_metadata_map, normalized_date)

      if is_nil(cache_hit_rate_metadata) or (cache_hit_rate_metadata.cacheable_tasks || 0) == 0 do
        %{
          date: date,
          cache_hit_rate: 0.0
        }
      else
        cacheable_tasks = cache_hit_rate_metadata.cacheable_tasks
        cacheable_task_local_hits = cache_hit_rate_metadata.cacheable_task_local_hits || 0
        cacheable_task_remote_hits = cache_hit_rate_metadata.cacheable_task_remote_hits || 0

        %{
          date: date,
          cache_hit_rate: (cacheable_task_local_hits + cacheable_task_remote_hits) / cacheable_tasks
        }
      end
    end)
  end

  def selective_testing_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    current_selective_testing_hit_rate =
      selective_testing_hit_rate(
        project_id,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        is_ci: is_ci
      )

    previous_selective_testing_hit_rate =
      selective_testing_hit_rate(
        project_id,
        start_datetime: DateTime.add(start_datetime, -days_delta, :day),
        end_datetime: start_datetime,
        is_ci: is_ci
      )

    selective_testing_hit_rates =
      selective_testing_hit_rates(project_id,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        date_period: date_period,
        is_ci: is_ci
      )

    dates = Enum.map(selective_testing_hit_rates, & &1.date)

    %{
      trend:
        trend(
          previous_value: previous_selective_testing_hit_rate,
          current_value: current_selective_testing_hit_rate
        ),
      hit_rate: current_selective_testing_hit_rate,
      dates: dates,
      values:
        Enum.map(
          selective_testing_hit_rates,
          & &1.hit_rate
        )
    }
  end

  def selective_testing_analytics_with_percentiles(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    is_ci = Keyword.get(opts, :is_ci)

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket_for_date_period(date_period))

    base_analytics = selective_testing_analytics(opts)

    [p50_period, p90_period, p99_period, p50_values, p90_values, p99_values] =
      Task.await_many(
        [
          Task.async(fn ->
            CommandEvents.selective_testing_hit_rate_period_percentile(
              project_id,
              start_datetime,
              end_datetime,
              0.50,
              is_ci: is_ci
            )
          end),
          Task.async(fn ->
            CommandEvents.selective_testing_hit_rate_period_percentile(
              project_id,
              start_datetime,
              end_datetime,
              0.90,
              is_ci: is_ci
            )
          end),
          Task.async(fn ->
            CommandEvents.selective_testing_hit_rate_period_percentile(
              project_id,
              start_datetime,
              end_datetime,
              0.99,
              is_ci: is_ci
            )
          end),
          Task.async(fn ->
            CommandEvents.selective_testing_hit_rate_percentiles(
              project_id,
              start_datetime,
              end_datetime,
              clickhouse_time_bucket,
              0.50,
              is_ci: is_ci
            )
          end),
          Task.async(fn ->
            CommandEvents.selective_testing_hit_rate_percentiles(
              project_id,
              start_datetime,
              end_datetime,
              clickhouse_time_bucket,
              0.90,
              is_ci: is_ci
            )
          end),
          Task.async(fn ->
            CommandEvents.selective_testing_hit_rate_percentiles(
              project_id,
              start_datetime,
              end_datetime,
              clickhouse_time_bucket,
              0.99,
              is_ci: is_ci
            )
          end)
        ],
        30_000
      )

    dates = base_analytics.dates

    Map.merge(base_analytics, %{
      p50: normalize_percentile_result(p50_period),
      p90: normalize_percentile_result(p90_period),
      p99: normalize_percentile_result(p99_period),
      p50_values: process_percentile_hit_rates(p50_values, dates, date_period),
      p90_values: process_percentile_hit_rates(p90_values, dates, date_period),
      p99_values: process_percentile_hit_rates(p99_values, dates, date_period)
    })
  end

  defp normalize_percentile_result(nil), do: 0.0
  defp normalize_percentile_result(value) when is_float(value), do: value
  defp normalize_percentile_result(%Decimal{} = value), do: Decimal.to_float(value)

  defp process_percentile_hit_rates(percentile_data, dates, date_period) do
    percentile_map =
      Map.new(percentile_data, fn row -> {normalise_date(row.date, date_period), row.percentile_hit_rate} end)

    Enum.map(dates, fn date ->
      normalized_date = normalise_date(date, date_period)

      case Map.get(percentile_map, normalized_date) do
        nil -> 0.0
        value -> value / 100.0
      end
    end)
  end

  defp selective_testing_hit_rate(project_id, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = DateTime.utc_now()

    result =
      CommandEvents.selective_testing_hit_rate(project_id, start_datetime, end_datetime, opts)

    local_test_hits_count = result.local_test_hits_count || 0
    remote_test_hits_count = result.remote_test_hits_count || 0
    test_targets_count = result.test_targets_count || 0

    if test_targets_count == 0 do
      0.0
    else
      (local_test_hits_count + remote_test_hits_count) / test_targets_count
    end
  end

  defp selective_testing_hit_rates(project_id, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    selective_testing_hit_rate_metadata_map =
      project_id
      |> CommandEvents.selective_testing_hit_rates(
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )
      |> Map.new(
        &{normalise_date(&1.date, date_period),
         %{
           test_targets: &1.test_targets,
           local_test_target_hits: &1.local_test_target_hits,
           remote_test_target_hits: &1.remote_test_target_hits
         }}
      )

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      selective_testing_hit_rate_metadata = Map.get(selective_testing_hit_rate_metadata_map, normalized_date)

      if is_nil(selective_testing_hit_rate_metadata) or
           (selective_testing_hit_rate_metadata.test_targets || 0) == 0 do
        %{
          date: date,
          hit_rate: 0.0
        }
      else
        test_targets = selective_testing_hit_rate_metadata.test_targets
        local_test_target_hits = selective_testing_hit_rate_metadata.local_test_target_hits || 0
        remote_test_target_hits = selective_testing_hit_rate_metadata.remote_test_target_hits || 0

        %{
          date: date,
          hit_rate: (local_test_target_hits + remote_test_target_hits) / test_targets
        }
      end
    end)
  end

  def build_time_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(xg in XcodeGraph,
        join: e in Event,
        on: xg.command_event_id == e.id,
        where: xg.inserted_at > ^start_datetime,
        where: xg.inserted_at < ^end_datetime,
        select: %{
          actual_build_time: sum(e.duration),
          total_time_saved: sum(xg.binary_build_duration)
        }
      )

    query =
      case project_id do
        nil -> query
        _ -> where(query, [xg, e], e.project_id == ^project_id)
      end

    query =
      case is_ci do
        nil -> query
        true -> where(query, [xg, e], e.is_ci == true)
        false -> where(query, [xg, e], e.is_ci == false)
      end

    result = ClickHouseRepo.one(query) || %{actual_build_time: 0, total_time_saved: 0}

    actual = normalize_duration_result(result.actual_build_time)
    saved = result.total_time_saved || 0
    total = actual + saved

    %{
      actual_build_time: actual,
      total_time_saved: saved,
      total_build_time: total
    }
  end

  defp normalize_duration_result(result) do
    case result do
      nil -> 0
      %Decimal{} -> Decimal.to_integer(result)
      value when is_integer(value) -> value
      value when is_float(value) -> round(value)
    end
  end

  def combined_builds_analytics(project_id, opts \\ []) do
    queries = [
      fn -> build_duration_analytics(project_id, opts) end,
      fn -> build_percentile_durations(project_id, 0.99, opts) end,
      fn -> build_percentile_durations(project_id, 0.9, opts) end,
      fn -> build_percentile_durations(project_id, 0.5, opts) end,
      fn -> build_analytics(project_id, opts) end,
      fn -> build_analytics(project_id, Keyword.put(opts, :status, :failure)) end,
      fn -> build_success_rate_analytics(project_id, opts) end
    ]

    Tasks.parallel_tasks(queries)
  end

  @doc """
  Gets CAS upload analytics for a project over a time period.

  ## Options
    * `:start_date` - Start date for the analytics period
    * `:end_date` - End date for the analytics period
    * `:is_ci` - Filter by CI builds (true/false/nil for all)
  """
  def cas_uploads_analytics(project_id, opts \\ []) do
    cas_action_analytics(project_id, "upload", opts)
  end

  @doc """
  Gets CAS download analytics for a project over a time period.

  ## Options
    * `:start_date` - Start date for the analytics period
    * `:end_date` - End date for the analytics period
    * `:is_ci` - Filter by CI builds (true/false/nil for all)
  """
  def cas_downloads_analytics(project_id, opts \\ []) do
    cas_action_analytics(project_id, "download", opts)
  end

  defp cas_action_analytics(project_id, action, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    interval_str = time_bucket_to_clickhouse_interval(time_bucket)

    current_data =
      ClickHouseRepo.query!(
        """
        SELECT
          toStartOfInterval(inserted_at, INTERVAL #{interval_str}) as date,
          SUM(size) as total_size
        FROM cas_events
        WHERE project_id = {project_id:Int64}
          AND action = {action:String}
          AND inserted_at >= {start_dt:DateTime}
          AND inserted_at <= {end_dt:DateTime}
        GROUP BY date
        ORDER BY date
        """,
        %{
          project_id: project_id,
          action: action,
          start_dt: start_datetime,
          end_dt: end_datetime
        }
      )

    current_total = total_cas_size(project_id, action, start_datetime, end_datetime)

    previous_start_datetime = DateTime.add(start_datetime, -days_delta, :day)
    previous_total = total_cas_size(project_id, action, previous_start_datetime, start_datetime)

    processed_data =
      current_data.rows
      |> Enum.map(fn [date, size] -> %{date: date, size: size} end)
      |> process_cas_data(start_datetime, end_datetime, date_period)

    %{
      trend: trend(previous_value: previous_total, current_value: current_total),
      total_size: current_total,
      dates: Enum.map(processed_data, & &1.date),
      values: Enum.map(processed_data, & &1.size)
    }
  end

  defp total_cas_size(project_id, action, start_datetime, end_datetime) do
    result =
      ClickHouseRepo.query!(
        """
        SELECT SUM(size) as total_size
        FROM cas_events
        WHERE project_id = {project_id:Int64}
          AND action = {action:String}
          AND inserted_at >= {start_dt:DateTime}
          AND inserted_at <= {end_dt:DateTime}
        """,
        %{
          project_id: project_id,
          action: action,
          start_dt: start_datetime,
          end_dt: end_datetime
        }
      )

    case result.rows do
      [[nil]] -> 0
      [[size]] -> size
      _ -> 0
    end
  end

  defp process_cas_data(cas_data, start_datetime, end_datetime, date_period) do
    cas_map =
      case cas_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.size})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      size = Map.get(cas_map, normalized_date, 0)
      %{date: date, size: size}
    end)
  end

  @doc """
  Gets build cache hit rate analytics for a project over a time period.

  ## Options
    * `:start_date` - Start date for the analytics period
    * `:end_date` - End date for the analytics period
    * `:is_ci` - Filter by CI builds (true/false/nil for all)
  """
  def build_cache_hit_rate_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_datetime and
            b.inserted_at <= ^end_datetime and
            b.cacheable_tasks_count > 0
      )

    query = query_with_is_ci_filter(query, opts)

    time_bucket = time_bucket_for_date_period(date_period)

    current_data =
      Repo.all(
        from(b in query,
          group_by: selected_as(:date_bucket),
          select: %{
            date: selected_as(time_bucket(b.inserted_at, ^time_bucket), :date_bucket),
            hit_rate:
              fragment(
                "CASE WHEN SUM(?) = 0 THEN 0.0 ELSE (SUM(?) + SUM(?))::float / SUM(?) * 100.0 END",
                b.cacheable_tasks_count,
                b.cacheable_task_local_hits_count,
                b.cacheable_task_remote_hits_count,
                b.cacheable_tasks_count
              )
          },
          order_by: [asc: selected_as(:date_bucket)]
        )
      )

    current_avg_hit_rate = avg_cache_hit_rate(project_id, start_datetime, end_datetime, opts)

    previous_start_datetime = DateTime.add(start_datetime, -days_delta, :day)
    previous_avg_hit_rate = avg_cache_hit_rate(project_id, previous_start_datetime, start_datetime, opts)

    processed_data =
      process_hit_rate_data(current_data, start_datetime, end_datetime, date_period)

    %{
      trend:
        trend(
          previous_value: previous_avg_hit_rate,
          current_value: current_avg_hit_rate
        ),
      avg_hit_rate: current_avg_hit_rate,
      dates: Enum.map(processed_data, & &1.date),
      values: Enum.map(processed_data, & &1.hit_rate)
    }
  end

  @doc """
  Gets percentile cache hit rate analytics for a project over a time period.

  Note: For cache hit rate, higher values are better, so percentiles are calculated
  in descending order. For example, p90 = 60% means that 90% of builds achieved
  a hit rate of 60% or better (not 60% or worse).

  ## Parameters
    * `project_id` - The project ID
    * `percentile` - The percentile to calculate (e.g., 0.5, 0.9, 0.99)
    * `opts` - Options including:
      * `:start_date` - Start date for the analytics period
      * `:end_date` - End date for the analytics period
      * `:is_ci` - Filter by CI builds (true/false/nil for all)

  ## Returns
    A map with:
    * `:trend` - Percentage change from previous period
    * `:total_percentile_hit_rate` - The percentile hit rate for the current period
    * `:dates` - List of dates for the chart
    * `:values` - List of percentile hit rate values
  """
  def build_cache_hit_rate_percentile(project_id, percentile, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    current_period_percentile =
      cache_hit_rate_period_percentile(project_id, percentile, start_datetime, end_datetime, opts)

    previous_period_percentile =
      cache_hit_rate_period_percentile(
        project_id,
        percentile,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        opts
      )

    time_bucket = time_bucket_for_date_period(date_period)

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_datetime and
            b.inserted_at <= ^end_datetime and
            b.cacheable_tasks_count > 0
      )

    query = query_with_is_ci_filter(query, opts)

    hit_rate_data =
      Repo.all(
        from(b in query,
          group_by: selected_as(:date_bucket),
          select: %{
            date: selected_as(time_bucket(b.inserted_at, ^time_bucket), :date_bucket),
            hit_rate:
              fragment(
                "percentile_cont(?) within group (order by ((? + ?)::float / ? * 100.0) DESC)",
                ^percentile,
                b.cacheable_task_local_hits_count,
                b.cacheable_task_remote_hits_count,
                b.cacheable_tasks_count
              )
          },
          order_by: [asc: selected_as(:date_bucket)]
        )
      )

    processed_data = process_hit_rate_data(hit_rate_data, start_datetime, end_datetime, date_period)

    %{
      trend:
        trend(
          previous_value: previous_period_percentile,
          current_value: current_period_percentile
        ),
      total_percentile_hit_rate: current_period_percentile,
      dates: Enum.map(processed_data, & &1.date),
      values: Enum.map(processed_data, & &1.hit_rate)
    }
  end

  defp cache_hit_rate_period_percentile(project_id, percentile, start_datetime, end_datetime, opts) do
    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_datetime and
            b.inserted_at <= ^end_datetime and
            b.cacheable_tasks_count > 0,
        select:
          fragment(
            "percentile_cont(?) within group (order by ((? + ?)::float / ? * 100.0) DESC)",
            ^percentile,
            b.cacheable_task_local_hits_count,
            b.cacheable_task_remote_hits_count,
            b.cacheable_tasks_count
          )
      )

    query = query_with_is_ci_filter(query, opts)

    result = Repo.one(query)
    normalize_result(result)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp avg_cache_hit_rate(project_id, start_datetime, end_datetime, opts) do
    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_datetime and
            b.inserted_at <= ^end_datetime and
            b.cacheable_tasks_count > 0,
        select: %{
          total_cacheable: sum(b.cacheable_tasks_count),
          total_local_hits: sum(b.cacheable_task_local_hits_count),
          total_remote_hits: sum(b.cacheable_task_remote_hits_count)
        }
      )

    query = query_with_is_ci_filter(query, opts)

    result = Repo.one(query)

    case result do
      nil ->
        0.0

      %{total_cacheable: total} when is_nil(total) or total == 0 ->
        0.0

      %{total_cacheable: total, total_local_hits: local, total_remote_hits: remote} ->
        local = local || 0
        remote = remote || 0
        Float.round((local + remote) / total * 100.0, 1)
    end
  end

  defp process_hit_rate_data(hit_rate_data, start_datetime, end_datetime, date_period) do
    hit_rate_map =
      case hit_rate_data do
        data when is_list(data) ->
          Map.new(data, fn item ->
            date = normalise_date(item.date, date_period)
            hit_rate = if is_nil(item.hit_rate), do: 0.0, else: Float.round(item.hit_rate, 1)
            {date, hit_rate}
          end)

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      hit_rate = Map.get(hit_rate_map, normalized_date, 0.0)
      %{date: date, hit_rate: hit_rate}
    end)
  end

  @doc """
  Gets Xcode build cache metrics from the Builds table.

  Returns a map with:
  - cacheable_tasks_count: Total number of cacheable tasks
  - cacheable_task_local_hits_count: Total number of local cache hits
  - cacheable_task_remote_hits_count: Total number of remote cache hits
  """
  def build_cache_hit_rate(project_id, start_datetime, end_datetime, opts) do
    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_datetime and
            b.inserted_at <= ^end_datetime and
            b.cacheable_tasks_count > 0,
        select: %{
          cacheable_tasks_count: sum(b.cacheable_tasks_count),
          cacheable_task_local_hits_count: sum(b.cacheable_task_local_hits_count),
          cacheable_task_remote_hits_count: sum(b.cacheable_task_remote_hits_count)
        }
      )

    query = query_with_is_ci_filter(query, opts)

    result = Repo.one(query)

    %{
      cacheable_tasks_count: result.cacheable_tasks_count || 0,
      cacheable_task_local_hits_count: result.cacheable_task_local_hits_count || 0,
      cacheable_task_remote_hits_count: result.cacheable_task_remote_hits_count || 0
    }
  end

  @doc """
  Gets Xcode build cache metrics over time from the Builds table.

  Returns a list of maps, one for each time period, with:
  - date: The date string for the period
  - cacheable_tasks: Total number of cacheable tasks in this period
  - cacheable_task_local_hits: Total number of local cache hits in this period
  - cacheable_task_remote_hits: Total number of remote cache hits in this period
  """
  def build_cache_hit_rates(project_id, start_datetime, end_datetime, time_bucket, opts) do
    pg_time_bucket = clickhouse_interval_to_postgrex_interval(time_bucket)

    query =
      from(b in Build,
        group_by: selected_as(:date_bucket),
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_datetime and
            b.inserted_at <= ^end_datetime and
            b.cacheable_tasks_count > 0,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^pg_time_bucket), :date_bucket),
          cacheable_tasks: sum(b.cacheable_tasks_count),
          cacheable_task_local_hits: sum(b.cacheable_task_local_hits_count),
          cacheable_task_remote_hits: sum(b.cacheable_task_remote_hits_count)
        },
        order_by: [asc: selected_as(:date_bucket)]
      )

    query = query_with_is_ci_filter(query, opts)

    results = Repo.all(query)

    date_format = get_clickhouse_date_format(time_bucket)

    Enum.map(results, fn result ->
      date_str =
        case result.date do
          %DateTime{} = dt -> format_datetime_for_date_format(dt, date_format)
          %NaiveDateTime{} = dt -> format_datetime_for_date_format(dt, date_format)
        end

      %{
        date: date_str,
        cacheable_tasks: result.cacheable_tasks || 0,
        cacheable_task_local_hits: result.cacheable_task_local_hits || 0,
        cacheable_task_remote_hits: result.cacheable_task_remote_hits || 0
      }
    end)
  end

  @doc """
  Runs all cache analytics queries in parallel for a project.

  Returns a list of analytics maps:
  [uploads_analytics, downloads_analytics, hit_rate_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50]
  """
  def combined_cache_analytics(project_id, opts \\ []) do
    queries = [
      fn -> cas_uploads_analytics(project_id, opts) end,
      fn -> cas_downloads_analytics(project_id, opts) end,
      fn -> build_cache_hit_rate_analytics(project_id, opts) end,
      fn -> build_cache_hit_rate_percentile(project_id, 0.99, opts) end,
      fn -> build_cache_hit_rate_percentile(project_id, 0.9, opts) end,
      fn -> build_cache_hit_rate_percentile(project_id, 0.5, opts) end
    ]

    Tasks.parallel_tasks(queries)
  end

  @doc """
  Gets module cache hit rate analytics for a project over a time period.

  ## Options
    * `:project_id` - The project ID
    * `:start_date` - Start date for the analytics period
    * `:end_date` - End date for the analytics period

  ## Returns
    A map with:
    * `:avg_hit_rate` - Average hit rate as a percentage
    * `:trend` - Percentage change from previous period
    * `:dates` - List of dates for the chart
    * `:values` - List of hit rate values (as percentages)
  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def module_cache_hit_rate_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    hit_rate_result = CommandEvents.cache_hit_rate(project_id, start_datetime, end_datetime, opts)

    hit_rate_time_series =
      CommandEvents.cache_hit_rates(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    cacheable = hit_rate_result.cacheable_targets_count || 0
    local_hits = hit_rate_result.local_cache_hits_count || 0
    remote_hits = hit_rate_result.remote_cache_hits_count || 0
    total_hits = local_hits + remote_hits
    avg_hit_rate = calculate_hit_rate_percentage(total_hits, cacheable)

    previous_start = DateTime.add(start_datetime, -days_delta, :day)
    previous_result = CommandEvents.cache_hit_rate(project_id, previous_start, start_datetime, opts)
    previous_cacheable = previous_result.cacheable_targets_count || 0
    previous_hits = (previous_result.local_cache_hits_count || 0) + (previous_result.remote_cache_hits_count || 0)

    previous_hit_rate = calculate_hit_rate_percentage(previous_hits, previous_cacheable)

    hit_rate_trend = trend(previous_value: previous_hit_rate, current_value: avg_hit_rate)

    all_dates = generate_date_range(start_datetime, end_datetime, date_period)

    hit_rate_map =
      Map.new(hit_rate_time_series, fn item ->
        cacheable = item.cacheable_targets || 0
        local = item.local_cache_target_hits || 0
        remote = item.remote_cache_target_hits || 0
        normalized_date = normalize_clickhouse_date(item.date, date_period)
        {normalized_date, calculate_hit_rate_percentage(local + remote, cacheable)}
      end)

    {hit_rate_dates, hit_rate_values} =
      fill_date_range_with_values(all_dates, date_period, hit_rate_map, 0.0)

    %{
      avg_hit_rate: avg_hit_rate,
      trend: hit_rate_trend,
      dates: hit_rate_dates,
      values: hit_rate_values
    }
  end

  @doc """
  Gets module cache hits analytics for a project over a time period.

  ## Options
    * `:project_id` - The project ID
    * `:start_date` - Start date for the analytics period
    * `:end_date` - End date for the analytics period

  ## Returns
    A map with:
    * `:total_count` - Total number of cache hits
    * `:trend` - Percentage change from previous period
    * `:dates` - List of dates for the chart
    * `:values` - List of hit count values
  """
  def module_cache_hits_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    hit_rate_time_series =
      CommandEvents.cache_hit_rates(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    all_dates = generate_date_range(start_datetime, end_datetime, date_period)

    hits_map =
      Map.new(hit_rate_time_series, fn item ->
        hits = (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
        normalized_date = normalize_clickhouse_date(item.date, date_period)
        {normalized_date, hits}
      end)

    {hit_rate_dates, hits_values} =
      fill_date_range_with_values(all_dates, date_period, hits_map, 0)

    total_hits_count = Enum.sum(hits_values)

    previous_start = DateTime.add(start_datetime, -days_delta, :day)

    previous_hits_series =
      CommandEvents.cache_hit_rates(
        project_id,
        previous_start,
        start_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    previous_total_hits =
      Enum.reduce(previous_hits_series, 0, fn item, acc ->
        acc + (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
      end)

    hits_trend = trend(previous_value: previous_total_hits, current_value: total_hits_count)

    %{
      total_count: total_hits_count,
      trend: hits_trend,
      dates: hit_rate_dates,
      values: hits_values
    }
  end

  @doc """
  Gets module cache misses analytics for a project over a time period.

  ## Options
    * `:project_id` - The project ID
    * `:start_date` - Start date for the analytics period
    * `:end_date` - End date for the analytics period

  ## Returns
    A map with:
    * `:total_count` - Total number of cache misses
    * `:trend` - Percentage change from previous period
    * `:dates` - List of dates for the chart
    * `:values` - List of miss count values
  """
  def module_cache_misses_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    hit_rate_time_series =
      CommandEvents.cache_hit_rates(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    all_dates = generate_date_range(start_datetime, end_datetime, date_period)

    misses_map =
      Map.new(hit_rate_time_series, fn item ->
        cacheable = item.cacheable_targets || 0
        hits = (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
        normalized_date = normalize_clickhouse_date(item.date, date_period)
        {normalized_date, max(0, cacheable - hits)}
      end)

    {hit_rate_dates, misses_values} =
      fill_date_range_with_values(all_dates, date_period, misses_map, 0)

    total_misses_count = Enum.sum(misses_values)

    previous_start = DateTime.add(start_datetime, -days_delta, :day)

    previous_hits_series =
      CommandEvents.cache_hit_rates(
        project_id,
        previous_start,
        start_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    previous_total_misses =
      Enum.reduce(previous_hits_series, 0, fn item, acc ->
        cacheable = item.cacheable_targets || 0
        hits = (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
        acc + max(0, cacheable - hits)
      end)

    misses_trend = trend(previous_value: previous_total_misses, current_value: total_misses_count)

    %{
      total_count: total_misses_count,
      trend: misses_trend,
      dates: hit_rate_dates,
      values: misses_values
    }
  end

  @doc """
  Gets module cache hit rate percentile analytics for a project over a time period.

  This function calculates percentile-based hit rates by analyzing individual runs
  and determining what percentage of runs achieved a certain hit rate or better.

  Note: For cache hit rate, higher values are better, so percentiles are calculated
  in descending order. For example, p99 = 60% means that 99% of runs achieved
  a hit rate of 60% or better (not 60% or worse).

  ## Parameters
    * `project_id` - The project ID
    * `percentile` - The percentile to calculate (e.g., 0.5, 0.9, 0.99)
    * `opts` - Options including:
      * `:start_date` - Start date for the analytics period
      * `:end_date` - End date for the analytics period

  ## Returns
    A map with:
    * `:avg_hit_rate` - The percentile hit rate as a percentage
    * `:trend` - Percentage change from previous period
    * `:dates` - List of dates for the chart
    * `:values` - List of percentile hit rate values (as percentages)
  """
  def module_cache_hit_rate_percentile(project_id, percentile, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_period_percentile =
      module_cache_hit_rate_period_percentile(project_id, percentile, start_datetime, end_datetime, opts)

    previous_start = DateTime.add(start_datetime, -days_delta, :day)

    previous_period_percentile =
      module_cache_hit_rate_period_percentile(project_id, percentile, previous_start, start_datetime, opts)

    percentile_time_series =
      CommandEvents.cache_hit_rate_percentiles(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        percentile,
        opts
      )

    all_dates = generate_date_range(start_datetime, end_datetime, date_period)

    percentile_map =
      Map.new(percentile_time_series, fn item ->
        value = if item.percentile_hit_rate, do: Float.round(item.percentile_hit_rate, 1), else: 0.0
        normalized_date = normalize_clickhouse_date(item.date, date_period)
        {normalized_date, value}
      end)

    {percentile_dates, percentile_values} =
      fill_date_range_with_values(all_dates, date_period, percentile_map, 0.0)

    %{
      avg_hit_rate: current_period_percentile,
      trend: trend(previous_value: previous_period_percentile, current_value: current_period_percentile),
      dates: percentile_dates,
      values: percentile_values
    }
  end

  defp module_cache_hit_rate_period_percentile(project_id, percentile, start_datetime, end_datetime, opts) do
    result = CommandEvents.cache_hit_rate_period_percentile(project_id, start_datetime, end_datetime, percentile, opts)

    case result do
      nil -> 0.0
      value when is_float(value) -> Float.round(value, 1)
      value -> Float.round(value * 1.0, 1)
    end
  end

  @doc """
  Gets a single build duration metric for the last N builds.

  ## Parameters
    * `project_id` - The project ID
    * `metric` - The metric to calculate: `:p50`, `:p90`, `:p99`, or `:average`
    * `opts` - Options:
      * `:limit` - Number of builds to consider (default: 100)
      * `:offset` - Number of builds to skip (default: 0)

  ## Returns
    The calculated metric value, or `nil` if no data available.
  """
  def build_duration_metric_by_count(project_id, metric, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    durations =
      Repo.all(
        from(b in Build,
          where: b.project_id == ^project_id,
          order_by: [desc: b.inserted_at],
          limit: ^limit,
          offset: ^offset,
          select: b.duration
        )
      )

    calculate_metric_from_values(durations, metric)
  end

  @doc """
  Gets a single cache hit rate metric for the last N builds.

  ## Parameters
    * `project_id` - The project ID
    * `metric` - The metric to calculate: `:p50`, `:p90`, `:p99`, or `:average`
    * `opts` - Options:
      * `:limit` - Number of builds to consider (default: 100)
      * `:offset` - Number of builds to skip (default: 0)

  ## Returns
    The calculated metric value (as a ratio 0.0-1.0), or `nil` if no data available.
  """
  def build_cache_hit_rate_metric_by_count(project_id, metric, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    hit_rates =
      Repo.all(
        from(b in Build,
          where:
            b.project_id == ^project_id and
              not is_nil(b.cacheable_tasks_count) and
              b.cacheable_tasks_count > 0,
          order_by: [desc: b.inserted_at],
          limit: ^limit,
          offset: ^offset,
          select:
            fragment(
              "(COALESCE(?, 0) + COALESCE(?, 0))::float / ?",
              b.cacheable_task_local_hits_count,
              b.cacheable_task_remote_hits_count,
              b.cacheable_tasks_count
            )
        )
      )

    calculate_hit_rate_metric_from_values(hit_rates, metric)
  end

  defp calculate_metric_from_values([], _metric), do: nil

  defp calculate_metric_from_values(values, :average) do
    Enum.sum(values) / length(values)
  end

  defp calculate_metric_from_values(values, percentile) do
    sorted = Enum.sort(values)
    count = length(sorted)

    index =
      case percentile do
        :p50 -> trunc(count * 0.5)
        :p90 -> trunc(count * 0.9)
        :p99 -> trunc(count * 0.99)
      end

    index = min(index, count - 1)
    Enum.at(sorted, index)
  end

  defp calculate_hit_rate_metric_from_values([], _metric), do: nil

  defp calculate_hit_rate_metric_from_values(values, :average) do
    Enum.sum(values) / length(values)
  end

  defp calculate_hit_rate_metric_from_values(values, percentile) do
    sorted = Enum.sort(values)
    count = length(sorted)

    index =
      case percentile do
        :p50 -> trunc(count * 0.5)
        :p90 -> trunc(count * 0.1)
        :p99 -> trunc(count * 0.01)
      end

    index = min(index, count - 1)
    Enum.at(sorted, index)
  end

  # Shared helper functions

  defp normalize_result(nil), do: 0.0
  defp normalize_result(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp normalize_result(float) when is_float(float), do: float
  defp normalize_result(int) when is_integer(int), do: int * 1.0

  defp calculate_hit_rate_percentage(_hits, total) when total == 0, do: 0.0
  defp calculate_hit_rate_percentage(hits, total), do: Float.round(hits / total * 100.0, 1)

  @doc """
  Returns the trend between the current value and the previous value as a percentage value. The value is negative if the current_value is smaller than previous_value.

  Returns 0 if the previous value is 0 or if the current value is 0.
  """
  def trend(opts) do
    previous_value = Keyword.get(opts, :previous_value)
    current_value = Keyword.get(opts, :current_value)

    case {previous_value, current_value} do
      {0, _} ->
        0.0

      {_, 0} ->
        0.0

      {+0.0, _} ->
        0.0

      {_, +0.0} ->
        0.0

      {previous_value, current_value} ->
        Float.round(
          current_value / previous_value * 100,
          1
        ) - 100.0
    end
  end

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
      :hour -> %Interval{secs: 3600}
      :day -> %Interval{days: 1}
      :month -> %Interval{months: 1}
    end
  end

  defp time_bucket_to_clickhouse_interval(%Interval{secs: 3600}), do: "1 hour"
  defp time_bucket_to_clickhouse_interval(%Interval{days: 1}), do: "1 day"
  defp time_bucket_to_clickhouse_interval(%Interval{months: 1}), do: "1 month"

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp add_filters(query, opts) do
    query = query_with_is_ci_filter(query, opts)

    scheme = Keyword.get(opts, :scheme)

    query =
      case scheme do
        nil -> query
        _ -> where(query, [e], e.scheme == ^scheme)
      end

    configuration = Keyword.get(opts, :configuration)

    query =
      case configuration do
        nil -> query
        _ -> where(query, [e], e.configuration == ^configuration)
      end

    category = Keyword.get(opts, :category)

    query =
      case category do
        nil -> query
        _ -> where(query, [e], e.category == ^category)
      end

    tag = Keyword.get(opts, :tag)

    query =
      case tag do
        nil -> query
        _ -> where(query, [e], ^tag in e.custom_tags)
      end

    status = Keyword.get(opts, :status)

    case status do
      nil -> query
      _ -> where(query, [e], e.status == ^status)
    end
  end

  defp query_with_is_ci_filter(query, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    case is_ci do
      nil -> query
      true -> where(query, [e], e.is_ci == true)
      false -> where(query, [e], e.is_ci == false)
    end
  end

  defp date_range_for_date_period(:hour, opts) do
    start_datetime = DateTime.truncate(Keyword.fetch!(opts, :start_datetime), :second)
    end_datetime = DateTime.truncate(Keyword.fetch!(opts, :end_datetime), :second)

    start_datetime
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
  end

  defp date_range_for_date_period(:month, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)

    start_datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> Date.range(Date.beginning_of_month(DateTime.to_date(end_datetime)))
    |> Enum.filter(&(&1.day == 1))
  end

  defp date_range_for_date_period(:day, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)

    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.to_list()
  end

  defp normalise_date(date_input, :hour) do
    case date_input do
      %DateTime{} = dt ->
        Timex.format!(dt, "%Y-%m-%d %H:00", :strftime)

      %NaiveDateTime{} = dt ->
        Timex.format!(dt, "%Y-%m-%d %H:00", :strftime)

      date_string when is_binary(date_string) ->
        date_string
        |> String.slice(0, 13)
        |> Kernel.<>(":00")

      %Date{} = d ->
        Timex.format!(d, "%Y-%m-%d", :strftime) <> " 00:00"
    end
  end

  defp normalise_date(date_input, date_period) do
    date =
      case date_input do
        %DateTime{} = dt ->
          DateTime.to_date(dt)

        %NaiveDateTime{} = dt ->
          NaiveDateTime.to_date(dt)

        date_string when is_binary(date_string) ->
          case Date.from_iso8601(date_string) do
            {:ok, date} -> date
            {:error, :invalid_format} -> Date.from_iso8601!(date_string <> "-01")
          end

        %Date{} = d ->
          d
      end

    case date_period do
      :day -> date
      :month -> Date.beginning_of_month(date)
    end
  end

  defp process_durations_data(durations_data, start_datetime, end_datetime, date_period) do
    durations_map =
      case durations_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.value})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      duration = Map.get(durations_map, normalized_date)

      %{
        date: date,
        value:
          case duration do
            nil -> 0
            duration when is_float(duration) -> duration
            _ -> Decimal.to_float(duration)
          end
      }
    end)
  end

  defp format_datetime_for_date_format(datetime, "%Y-%m-%d %H:00"),
    do: "#{Date.to_string(DateTime.to_date(datetime))} #{String.pad_leading(to_string(datetime.hour), 2, "0")}:00"

  defp format_datetime_for_date_format(datetime, "%Y-%m-%d"), do: Date.to_string(DateTime.to_date(datetime))

  defp format_datetime_for_date_format(datetime, "%Y-%m"),
    do: "#{datetime.year}-#{String.pad_leading(to_string(datetime.month), 2, "0")}"

  defp format_datetime_for_date_format(datetime, _), do: Date.to_string(DateTime.to_date(datetime))

  defp get_clickhouse_date_format("1 hour"), do: "%Y-%m-%d %H:00"
  defp get_clickhouse_date_format("1 day"), do: "%Y-%m-%d"
  defp get_clickhouse_date_format("1 month"), do: "%Y-%m"
  defp get_clickhouse_date_format(_), do: "%Y-%m-%d"

  defp clickhouse_interval_to_postgrex_interval("1 hour"), do: %Interval{secs: 3600}
  defp clickhouse_interval_to_postgrex_interval("1 day"), do: %Interval{days: 1}
  defp clickhouse_interval_to_postgrex_interval("1 month"), do: %Interval{months: 1}

  defp generate_date_range(start_datetime, end_datetime, :hour) do
    end_dt = DateTime.truncate(DateTime.utc_now(), :second)

    start_dt =
      case start_datetime do
        %DateTime{} = dt -> DateTime.truncate(dt, :second)
        nil -> DateTime.add(end_dt, -23, :hour)
      end

    actual_end_dt =
      case end_datetime do
        %DateTime{} = dt -> DateTime.truncate(dt, :second)
        nil -> end_dt
      end

    start_dt
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, actual_end_dt) != :gt))
  end

  defp generate_date_range(start_datetime, end_datetime, :day) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.to_list()
  end

  defp generate_date_range(start_datetime, end_datetime, :month) do
    start_datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> Date.range(Date.beginning_of_month(DateTime.to_date(end_datetime)))
    |> Enum.filter(&(&1.day == 1))
  end

  defp fill_date_range_with_values(all_dates, date_period, value_map, default_value) do
    all_dates
    |> Enum.map(fn date ->
      lookup_key = date_to_string(date, date_period)
      value = Map.get(value_map, lookup_key, default_value)
      {lookup_key, value}
    end)
    |> Enum.unzip()
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

  defp normalize_clickhouse_date(date_string, :hour) when is_binary(date_string) do
    date_string
    |> String.slice(0, 13)
    |> Kernel.<>(":00")
  end

  defp normalize_clickhouse_date(date_string, _date_period) when is_binary(date_string) do
    date_string
  end
end
