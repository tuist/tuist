defmodule Tuist.Runs.Analytics do
  @moduledoc """
  Module for run-related analytics, such as builds.
  """
  import Ecto.Query

  alias Postgrex.Interval
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.Runs.Build
  alias Tuist.Tasks
  alias Tuist.Xcode.XcodeGraph

  def build_duration_analytics_by_category(project_id, category, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    base_query =
      add_filters(
        from(b in Build, where: b.project_id == ^project_id and b.inserted_at >= ^start_nd and b.inserted_at <= ^end_nd),
        opts
      )

    query =
      case category do
        :xcode_version ->
          base_query
          |> group_by([b], b.xcode_version)
          |> select([b], %{category: b.xcode_version, value: avg(b.duration)})

        :model_identifier ->
          base_query
          |> group_by([b], b.model_identifier)
          |> select([b], %{category: b.model_identifier, value: avg(b.duration)})

        :macos_version ->
          base_query
          |> group_by([b], b.macos_version)
          |> select([b], %{category: b.macos_version, value: avg(b.duration)})
      end

    ClickHouseRepo.all(query)
  end

  def build_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)

    current_build_data =
      build_count(
        project_id,
        start_date,
        end_date,
        date_period,
        time_bucket,
        opts
      )

    previous_builds_count =
      build_total_count(project_id, Date.add(start_date, -days_delta), start_date, opts)

    current_builds_count = build_total_count(project_id, start_date, end_date, opts)

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

  defp build_count(project_id, start_date, end_date, date_period, time_bucket, opts) do
    time_bucket_interval = time_bucket_to_clickhouse_interval(time_bucket)
    date_format = get_date_format(time_bucket_interval)
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    date_range_query = build_date_range_query(start_date, end_date, date_period, date_format)

    data_query =
      add_filters(
        from(b in Build,
          group_by: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
          where: b.project_id == ^project_id and b.inserted_at >= ^start_nd and b.inserted_at <= ^end_nd,
          select: %{date: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format), count: count(b.id)}
        ),
        opts
      )

    from(dr in subquery(date_range_query),
      left_join: d in subquery(data_query),
      on: dr.date == d.date,
      select: %{
        date: dr.date,
        count: fragment("COALESCE(?, 0)", d.count)
      },
      order_by: dr.date
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn %{date: date, count: count} ->
      %{date: normalise_date(date, date_period), count: normalize_count_result(count)}
    end)
  end

  defp build_total_count(project_id, start_date, end_date, opts) do
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    from(b in Build,
      where:
        b.project_id == ^project_id and
          b.inserted_at >= ^start_nd and
          b.inserted_at <= ^end_nd,
      select: count(b.id)
    )
    |> add_filters(opts)
    |> ClickHouseRepo.one()
    |> normalize_count_result()
  end

  defp runs_total_count(project_id, start_date, end_date, name, opts) do
    CommandEvents.run_analytics(
      project_id,
      start_date,
      end_date,
      Keyword.put(opts, :name, name)
    )[:count] || 0
  end

  def build_duration_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)

    previous_period_data =
      build_aggregated_analytics(project_id, Date.add(start_date, -days_delta), start_date, opts)

    previous_period_total_average_duration = previous_period_data.average_duration

    current_period_data = build_aggregated_analytics(project_id, start_date, end_date, opts)
    current_period_total_average_duration = current_period_data.average_duration

    time_bucket_interval = time_bucket_to_clickhouse_interval(time_bucket)
    date_format = get_date_format(time_bucket_interval)
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    date_range_query = build_date_range_query(start_date, end_date, date_period, date_format)

    average_durations_query =
      add_filters(
        from(b in Build,
          group_by: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
          where: b.project_id == ^project_id and b.inserted_at >= ^start_nd and b.inserted_at <= ^end_nd,
          select: %{date: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format), value: avg(b.duration)}
        ),
        opts
      )

    average_durations_data =
      ClickHouseRepo.all(
        from(dr in subquery(date_range_query),
          left_join: d in subquery(average_durations_query),
          on: dr.date == d.date,
          select: %{
            date: dr.date,
            value: fragment("COALESCE(?, 0)", d.value)
          },
          order_by: dr.date
        )
      )

    average_durations =
      process_durations_data(average_durations_data, start_date, end_date, date_period)

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

  defp build_aggregated_analytics(project_id, start_date, end_date, opts) do
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    result =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_nd and
            b.inserted_at <= ^end_nd,
        select: %{
          total_duration: sum(b.duration),
          count: count(b.id),
          average_duration: avg(b.duration)
        }
      )
      |> add_filters(opts)
      |> ClickHouseRepo.one()

    case result do
      nil ->
        %{total_duration: 0, count: 0, average_duration: 0}

      %{total_duration: nil, count: count, average_duration: nil} ->
        %{total_duration: 0, count: count, average_duration: 0}

      %{total_duration: total, count: count, average_duration: avg} ->
        %{
          total_duration: normalize_numeric_result(total),
          count: normalize_count_result(count),
          average_duration: normalize_numeric_result(avg)
        }
    end
  end

  def build_percentile_durations(project_id, percentile, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())

    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)

    time_bucket_interval = time_bucket_to_clickhouse_interval(time_bucket)
    date_format = get_date_format(time_bucket_interval)
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    date_range_query = build_date_range_query(start_date, end_date, date_period, date_format)

    durations_query =
      add_filters(
        from(b in Build,
          group_by: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
          where: b.project_id == ^project_id and b.inserted_at >= ^start_nd and b.inserted_at <= ^end_nd,
          select: %{
            date: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
            value: fragment("quantileExact(toFloat64(?))(?)", ^percentile, b.duration)
          }
        ),
        opts
      )

    durations_data =
      ClickHouseRepo.all(
        from(dr in subquery(date_range_query),
          left_join: d in subquery(durations_query),
          on: dr.date == d.date,
          select: %{
            date: dr.date,
            value: fragment("COALESCE(?, 0)", d.value)
          },
          order_by: dr.date
        )
      )

    durations = process_durations_data(durations_data, start_date, end_date, date_period)

    %{
      dates: Enum.map(durations, & &1.date),
      values: Enum.map(durations, & &1.value)
    }
  end

  def runs_duration_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    previous_period_runs_aggregated_analytics =
      CommandEvents.run_analytics(
        project_id,
        Date.add(start_date, -days_delta),
        start_date,
        Keyword.put(opts, :name, name)
      )

    previous_period_total_average_duration =
      previous_period_runs_aggregated_analytics[:average_duration] || 0

    current_period_runs_data =
      CommandEvents.run_analytics(
        project_id,
        start_date,
        end_date,
        Keyword.put(opts, :name, name)
      )

    total_average_duration = current_period_runs_data[:average_duration] || 0

    average_durations_data =
      CommandEvents.run_average_durations(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        name,
        opts
      )

    average_durations =
      process_durations_data(average_durations_data, start_date, end_date, date_period)

    %{
      trend:
        trend(
          previous_value: previous_period_total_average_duration,
          current_value: total_average_duration
        ),
      total_average_duration: total_average_duration,
      average_durations: average_durations,
      dates: Enum.map(average_durations, & &1.date),
      values: Enum.map(average_durations, & &1.value)
    }
  end

  defp process_durations_data(durations_data, start_date, end_date, date_period) do
    durations_map =
      case durations_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.value})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      duration = Map.get(durations_map, date)

      %{
        date: date,
        value:
          case duration do
            nil -> 0
            _ -> normalize_numeric_result(duration)
          end
      }
    end)
  end

  def runs_analytics(project_id, name, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_runs_data =
      CommandEvents.run_count(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        name,
        opts
      )

    current_runs = process_runs_count_data(current_runs_data, start_date, end_date, date_period)

    previous_runs_count =
      runs_total_count(project_id, Date.add(start_date, -days_delta), start_date, name, opts)

    current_runs_count = runs_total_count(project_id, start_date, end_date, name, opts)

    %{
      trend:
        trend(
          previous_value: previous_runs_count,
          current_value: current_runs_count
        ),
      count: current_runs_count,
      values: Enum.map(current_runs, & &1.count),
      dates: Enum.map(current_runs, & &1.date)
    }
  end

  defp process_runs_count_data(runs_data, start_date, end_date, date_period) do
    runs_map =
      case runs_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.count})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      count = Map.get(runs_map, date, 0)
      %{date: date, count: count}
    end)
  end

  def build_success_rate_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    current_success_rate =
      build_success_rate(
        project_id,
        start_date: start_date,
        end_date: end_date,
        opts: opts
      )

    previous_success_rate =
      build_success_rate(
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date,
        opts: opts
      )

    success_rates =
      build_success_rates_per_period(project_id,
        start_date: start_date,
        end_date: end_date,
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
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())
    filter_opts = Keyword.get(opts, :opts, [])

    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    result =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_nd and
            b.inserted_at <= ^end_nd,
        select: %{
          total_builds: count(b.id),
          successful_builds: fragment("countIf(? = 0)", b.status)
        }
      )
      |> add_filters(filter_opts)
      |> ClickHouseRepo.one()
      |> Kernel.||(%{total_builds: 0, successful_builds: 0})

    total_builds = normalize_count_result(result.total_builds)
    successful_builds = normalize_count_result(result.successful_builds)

    if total_builds == 0 do
      0.0
    else
      successful_builds / total_builds
    end
  end

  defp build_success_rates_per_period(project_id, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)
    filter_opts = Keyword.get(opts, :opts, [])

    time_bucket = time_bucket_for_date_period(date_period)

    time_bucket_interval = time_bucket_to_clickhouse_interval(time_bucket)
    date_format = get_date_format(time_bucket_interval)
    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    date_range_query = build_date_range_query(start_date, end_date, date_period, date_format)

    success_rate_query =
      add_filters(
        from(b in Build,
          group_by: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
          where: b.project_id == ^project_id and b.inserted_at >= ^start_nd and b.inserted_at <= ^end_nd,
          select: %{
            date: fragment("formatDateTime(?, ?)", b.inserted_at, ^date_format),
            total_builds: count(b.id),
            successful_builds: fragment("countIf(? = 0)", b.status)
          }
        ),
        filter_opts
      )

    success_rate_metadata_map =
      from(dr in subquery(date_range_query),
        left_join: d in subquery(success_rate_query),
        on: dr.date == d.date,
        select: %{
          date: dr.date,
          total_builds: fragment("COALESCE(?, 0)", d.total_builds),
          successful_builds: fragment("COALESCE(?, 0)", d.successful_builds)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(fn %{date: date, total_builds: total, successful_builds: success} ->
        {
          normalise_date(date, date_period),
          %{
            total_builds: normalize_count_result(total),
            successful_builds: normalize_count_result(success)
          }
        }
      end)

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      success_rate_metadata = Map.get(success_rate_metadata_map, date)

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
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    current_cache_hit_rate =
      cache_hit_rate(
        project_id,
        start_date: start_date,
        end_date: end_date,
        is_ci: is_ci
      )

    previous_cache_hit_rate =
      cache_hit_rate(
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date,
        is_ci: is_ci
      )

    cache_hit_rates =
      cache_hit_rates(project_id,
        start_date: start_date,
        end_date: end_date,
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
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = today()

    result =
      CommandEvents.cache_hit_rate(project_id, start_date, end_date, opts)

    local_cache_hits_count = result.local_cache_hits_count || 0
    remote_cache_hits_count = result.remote_cache_hits_count || 0
    cacheable_targets_count = result.cacheable_targets_count || 0

    if cacheable_targets_count == 0 do
      0.0
    else
      (local_cache_hits_count + remote_cache_hits_count) / cacheable_targets_count
    end
  end

  defp cache_hit_rates(project_id, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    cache_hit_rate_metadata_map =
      project_id
      |> CommandEvents.cache_hit_rates(
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        opts
      )
      |> Map.new(
        &{normalise_date(&1.date, date_period),
         %{
           cacheable_targets: &1.cacheable_targets,
           local_cache_target_hits: &1.local_cache_target_hits,
           remote_cache_target_hits: &1.remote_cache_target_hits
         }}
      )

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      cache_hit_rate_metadata = Map.get(cache_hit_rate_metadata_map, date)

      if is_nil(cache_hit_rate_metadata) or (cache_hit_rate_metadata.cacheable_targets || 0) == 0 do
        %{
          date: date,
          cache_hit_rate: 0.0
        }
      else
        cacheable_targets = cache_hit_rate_metadata.cacheable_targets
        local_cache_target_hits = cache_hit_rate_metadata.local_cache_target_hits || 0
        remote_cache_target_hits = cache_hit_rate_metadata.remote_cache_target_hits || 0

        %{
          date: date,
          cache_hit_rate: (local_cache_target_hits + remote_cache_target_hits) / cacheable_targets
        }
      end
    end)
  end

  def selective_testing_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = Keyword.get(opts, :end_date, today())
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    current_selective_testing_hit_rate =
      selective_testing_hit_rate(
        project_id,
        start_date: start_date,
        end_date: end_date,
        is_ci: is_ci
      )

    previous_selective_testing_hit_rate =
      selective_testing_hit_rate(
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date,
        is_ci: is_ci
      )

    selective_testing_hit_rates =
      selective_testing_hit_rates(project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period,
        is_ci: is_ci
      )

    %{
      trend:
        trend(
          previous_value: previous_selective_testing_hit_rate,
          current_value: current_selective_testing_hit_rate
        ),
      hit_rate: current_selective_testing_hit_rate,
      dates:
        Enum.map(
          selective_testing_hit_rates,
          & &1.date
        ),
      values:
        Enum.map(
          selective_testing_hit_rates,
          & &1.hit_rate
        )
    }
  end

  defp selective_testing_hit_rate(project_id, opts) do
    start_date = Keyword.get(opts, :start_date, Date.add(today(), -30))
    end_date = today()

    result =
      CommandEvents.selective_testing_hit_rate(project_id, start_date, end_date, opts)

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
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    selective_testing_hit_rate_metadata_map =
      project_id
      |> CommandEvents.selective_testing_hit_rates(
        start_date,
        end_date,
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
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      selective_testing_hit_rate_metadata = Map.get(selective_testing_hit_rate_metadata_map, date)

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

  defp normalize_numeric_result(nil), do: 0.0

  defp normalize_numeric_result(%Decimal{} = decimal) do
    Decimal.to_float(decimal)
  end

  defp normalize_numeric_result(value) when is_integer(value), do: value / 1

  defp normalize_numeric_result(value) when is_float(value) do
    Float.round(value, 4)
  end

  defp normalize_count_result(nil), do: 0
  defp normalize_count_result(%Decimal{} = decimal), do: Decimal.to_integer(decimal)
  defp normalize_count_result(value) when is_integer(value), do: value
  defp normalize_count_result(value) when is_float(value), do: round(value)

  defp get_date_format("1 hour"), do: "%Y-%m-%d %H:00:00"
  defp get_date_format("1 day"), do: "%Y-%m-%d"
  defp get_date_format("1 week"), do: "%Y-%u"
  defp get_date_format("1 month"), do: "%Y-%m"
  defp get_date_format(_), do: "%Y-%m-%d"

  defp build_date_range_query(start_date, end_date, date_period, date_format) do
    case date_period do
      :day ->
        from(
          d in fragment(
            """
              SELECT formatDateTime(
                toDateTime(?) + INTERVAL number DAY,
                ?
              ) AS date
              FROM numbers(dateDiff('day', toDate(?), toDate(?)) + 1)
            """,
            ^start_of_day(start_date),
            ^date_format,
            ^to_date(start_date),
            ^to_date(end_date)
          ),
          select: %{date: d.date}
        )

      :month ->
        from(
          d in fragment(
            """
              SELECT formatDateTime(
                toStartOfMonth(toDateTime(?) + INTERVAL number MONTH),
                ?
              ) AS date
              FROM numbers(dateDiff('month', toDate(?), toDate(?)) + 1)
            """,
            ^start_of_day(Date.beginning_of_month(to_date(start_date))),
            ^date_format,
            ^Date.beginning_of_month(to_date(start_date)),
            ^Date.beginning_of_month(to_date(end_date))
          ),
          select: %{date: d.date}
        )
    end
  end

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
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    days_delta = Date.diff(end_date, start_date)

    if days_delta >= 60 do
      :month
    else
      :day
    end
  end

  defp time_bucket_for_date_period(date_period) do
    case date_period do
      :day -> %Interval{days: 1}
      :month -> %Interval{months: 1}
    end
  end

  defp time_bucket_to_clickhouse_interval(%Interval{days: 1}), do: "1 day"
  defp time_bucket_to_clickhouse_interval(%Interval{months: 1}), do: "1 month"

  defp start_of_day(date) do
    date
    |> to_date()
    |> NaiveDateTime.new!(~T[00:00:00])
  end

  defp end_of_day(date) do
    date
    |> to_date()
    |> NaiveDateTime.new!(~T[23:59:59])
  end

  defp today do
    DateTime.to_date(DateTime.utc_now())
  end

  defp to_date(%Date{} = date), do: date
  defp to_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp to_date(date) when is_binary(date), do: Date.from_iso8601!(date)

  defp add_filters(query, opts) do
    query = query_with_is_ci_filter(query, opts)

    scheme = Keyword.get(opts, :scheme)

    query =
      case scheme do
        nil -> query
        _ -> where(query, [b], b.scheme == ^scheme)
      end

    configuration = Keyword.get(opts, :configuration)

    query =
      case configuration do
        nil -> query
        _ -> where(query, [b], b.configuration == ^configuration)
      end

    category = Keyword.get(opts, :category)

    query =
      case category do
        nil -> query
        category -> where(query, [b], b.category == ^category)
      end

    status_value = Keyword.get(opts, :status)

    case status_value do
      nil -> query
      status -> where(query, [b], b.status == ^status)
    end
  end

  defp query_with_is_ci_filter(query, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    case is_ci do
      nil -> query
      true -> where(query, [b], b.is_ci == true)
      false -> where(query, [b], b.is_ci == false)
    end
  end

  defp date_range_for_date_period(date_period, opts) do
    start_date = opts |> Keyword.get(:start_date) |> to_date()
    end_date = opts |> Keyword.get(:end_date) |> to_date()

    start_date
    |> Date.range(end_date)
    |> Enum.filter(fn date ->
      case date_period do
        :month ->
          date.day == 1

        :day ->
          true
      end
    end)
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

  def build_time_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(Date.utc_today(), -30))
    end_date = Keyword.get(opts, :end_date, Date.utc_today())
    is_ci = Keyword.get(opts, :is_ci)

    start_nd = start_of_day(start_date)
    end_nd = end_of_day(end_date)

    query =
      from(xg in XcodeGraph,
        join: e in Event,
        on: xg.command_event_id == e.id,
        where: xg.inserted_at >= ^start_nd,
        where: xg.inserted_at <= ^end_nd,
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
    saved = normalize_numeric_result(result.total_time_saved)
    total = actual + saved

    %{
      actual_build_time: actual,
      total_time_saved: saved,
      total_build_time: total
    }
  end

  defp normalize_duration_result(result) do
    normalize_numeric_result(result)
  end

  def combined_overview_analytics(project_id, opts \\ []) do
    queries = [
      fn -> cache_hit_rate_analytics(opts) end,
      fn -> selective_testing_analytics(opts) end,
      fn -> build_duration_analytics(project_id, opts) end,
      fn -> runs_duration_analytics("test", opts) end
    ]

    Tasks.parallel_tasks(queries)
  end

  def combined_builds_analytics(project_id, opts \\ []) do
    queries = [
      fn -> build_duration_analytics(project_id, opts) end,
      fn -> build_percentile_durations(project_id, 0.99, opts) end,
      fn -> build_percentile_durations(project_id, 0.9, opts) end,
      fn -> build_percentile_durations(project_id, 0.5, opts) end,
      fn -> build_analytics(project_id, opts) end,
      fn -> build_analytics(project_id, Keyword.put(opts, :status, "failure")) end,
      fn -> build_success_rate_analytics(project_id, opts) end
    ]

    Tasks.parallel_tasks(queries)
  end

  def combined_test_runs_analytics(project_id, opts \\ []) do
    queries = [
      fn -> runs_analytics(project_id, "test", opts) end,
      fn -> runs_analytics(project_id, "test", Keyword.put(opts, :status, "failure")) end,
      fn -> runs_duration_analytics("test", opts) end
    ]

    Tasks.parallel_tasks(queries)
  end
end
