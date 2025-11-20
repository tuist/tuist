defmodule Tuist.Runs.Analytics do
  @moduledoc """
  Module for run-related analytics, such as builds.
  """
  import Ecto.Query
  import Timescale.Hyperfunctions

  alias Postgrex.Interval
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.Repo
  alias Tuist.Runs.Build
  alias Tuist.Runs.Test
  alias Tuist.Tasks
  alias Tuist.Xcode.XcodeGraph

  def build_duration_analytics_by_category(project_id, category, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    query =
      where(
        from(b in Build),
        [b],
        b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
          b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and b.project_id == ^project_id
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

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
    builds_data =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
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
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      count = Map.get(builds_data, date, 0)
      %{date: date, count: count}
    end)
  end

  defp build_total_count(project_id, start_date, end_date, opts) do
    from(b in Build,
      where:
        b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
          b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
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

  defp runs_total_count(project_id, start_date, end_date, name, opts) do
    CommandEvents.run_analytics(
      project_id,
      start_date,
      end_date,
      Keyword.put(opts, :name, name)
    )[:count] || 0
  end

  def build_duration_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)

    previous_period_data =
      build_aggregated_analytics(project_id, Date.add(start_date, -days_delta), start_date, opts)

    previous_period_total_average_duration = previous_period_data.average_duration

    current_period_data = build_aggregated_analytics(project_id, start_date, end_date, opts)
    current_period_total_average_duration = current_period_data.average_duration

    average_durations_query =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            b.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
          value: avg(b.duration)
        }
      )
      |> add_filters(opts)
      |> Repo.all()

    average_durations =
      process_durations_data(average_durations_query, start_date, end_date, date_period)

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
    result =
      from(b in Build,
        where:
          b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)

    current_period_percentile =
      build_period_percentile(project_id, percentile, start_date, end_date, opts)

    previous_period_percentile =
      build_period_percentile(
        project_id,
        percentile,
        Date.add(start_date, -days_delta),
        start_date,
        opts
      )

    durations_data =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            b.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
          value: fragment("percentile_cont(?) within group (order by ?)", ^percentile, b.duration)
        }
      )
      |> add_filters(opts)
      |> Repo.all()

    durations = process_durations_data(durations_data, start_date, end_date, date_period)

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

  defp build_period_percentile(project_id, percentile, start_date, end_date, opts) do
    result =
      from(b in Build,
        where:
          b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
            b.project_id == ^project_id,
        select: fragment("percentile_cont(?) within group (order by ?)", ^percentile, b.duration)
      )
      |> add_filters(opts)
      |> Repo.one()

    normalize_result(result)
  end

  def runs_duration_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

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
            duration when is_float(duration) -> duration
            _ -> Decimal.to_float(duration)
          end
      }
    end)
  end

  def runs_analytics(project_id, name, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
    filter_opts = Keyword.get(opts, :opts, [])

    result =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]),
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
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)
    filter_opts = Keyword.get(opts, :opts, [])

    time_bucket = time_bucket_for_date_period(date_period)

    success_rate_metadata_map =
      from(b in Build,
        group_by: selected_as(^date_period),
        where:
          b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
            b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = DateTime.to_date(DateTime.utc_now())

    result = build_cache_hit_rate(project_id, start_date, end_date, opts)

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
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    cache_hit_rate_metadata_map =
      project_id
      |> build_cache_hit_rates(
        start_date,
        end_date,
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
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      cache_hit_rate_metadata = Map.get(cache_hit_rate_metadata_map, date)

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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = DateTime.to_date(DateTime.utc_now())

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

  defp normalize_result(nil), do: 0.0
  defp normalize_result(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp normalize_result(float) when is_float(float), do: float
  defp normalize_result(int) when is_integer(int), do: int * 1.0

  # Calculates hit rate as a percentage, handling division by zero.
  # Returns the hit rate as a percentage rounded to 1 decimal place.
  # Returns 0.0 if total is 0.
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

    status = Keyword.get(opts, :status)

    query =
      case status do
        nil -> query
        _ -> where(query, [e], e.status == ^status)
      end

    add_name_filter(query, opts)
  end

  defp query_with_is_ci_filter(query, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    case is_ci do
      nil -> query
      true -> where(query, [e], e.is_ci == true)
      false -> where(query, [e], e.is_ci == false)
    end
  end

  defp add_name_filter(query, opts) do
    name = Keyword.get(opts, :name)

    case name do
      "test" ->
        where(
          query,
          [e],
          (e.name == "xcodebuild" and
             (e.subcommand == "test" or e.subcommand == "test-without-building")) or
            e.name == "test"
        )

      _ ->
        query
    end
  end

  defp date_range_for_date_period(date_period, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

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

    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(xg in XcodeGraph,
        join: e in Event,
        on: xg.command_event_id == e.id,
        where: xg.inserted_at > ^start_dt,
        where: xg.inserted_at < ^end_dt,
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

  def test_run_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_runs_data =
      test_run_count(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    current_runs = process_runs_count_data(current_runs_data, start_date, end_date, date_period)

    previous_runs_count =
      test_run_total_count(project_id, Date.add(start_date, -days_delta), start_date, opts)

    current_runs_count = test_run_total_count(project_id, start_date, end_date, opts)

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

  defp test_run_count(project_id, start_date, end_date, _date_period, time_bucket, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)
    status = Keyword.get(opts, :status)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_dt,
        where: t.ran_at <= ^end_dt,
        group_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
          count: count(t.id)
        },
        order_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    query =
      case status do
        nil -> query
        "failure" -> where(query, [t], t.status == "failure")
        "success" -> where(query, [t], t.status == "success")
      end

    ClickHouseRepo.all(query)
  end

  defp test_run_total_count(project_id, start_date, end_date, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    is_ci = Keyword.get(opts, :is_ci)
    status = Keyword.get(opts, :status)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_dt,
        where: t.ran_at <= ^end_dt,
        select: count(t.id)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    query =
      case status do
        nil -> query
        "failure" -> where(query, [t], t.status == "failure")
        "success" -> where(query, [t], t.status == "success")
      end

    ClickHouseRepo.one(query) || 0
  end

  def test_run_duration_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    previous_period_total_average_duration =
      test_run_aggregated_duration(project_id, Date.add(start_date, -days_delta), start_date, opts)

    current_period_total_average_duration =
      test_run_aggregated_duration(project_id, start_date, end_date, opts)

    average_durations_data =
      test_run_average_durations(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        opts
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

  defp test_run_aggregated_duration(project_id, start_date, end_date, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_dt,
        where: t.ran_at <= ^end_dt,
        select: avg(t.duration)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    result = ClickHouseRepo.one(query)

    case result do
      nil -> 0.0
      avg when is_float(avg) -> avg
      avg -> avg * 1.0
    end
  end

  defp test_run_average_durations(project_id, start_date, end_date, _date_period, time_bucket, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_dt,
        where: t.ran_at <= ^end_dt,
        group_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
          value: avg(t.duration)
        },
        order_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    ClickHouseRepo.all(query)
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    interval_str = time_bucket_to_clickhouse_interval(time_bucket)

    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

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
          start_dt: start_dt,
          end_dt: end_dt
        }
      )

    current_total = total_cas_size(project_id, action, start_date, end_date)

    previous_start_date = Date.add(start_date, -days_delta)
    previous_total = total_cas_size(project_id, action, previous_start_date, start_date)

    processed_data =
      current_data.rows
      |> Enum.map(fn [date, size] -> %{date: date, size: size} end)
      |> process_cas_data(start_date, end_date, date_period)

    %{
      trend: trend(previous_value: previous_total, current_value: current_total),
      total_size: current_total,
      dates: Enum.map(processed_data, & &1.date),
      values: Enum.map(processed_data, & &1.size)
    }
  end

  defp total_cas_size(project_id, action, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

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
          start_dt: start_dt,
          end_dt: end_dt
        }
      )

    case result.rows do
      [[nil]] -> 0
      [[size]] -> size
      _ -> 0
    end
  end

  defp process_cas_data(cas_data, start_date, end_date, date_period) do
    cas_map =
      case cas_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.size})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      size = Map.get(cas_map, date, 0)
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_dt and
            b.inserted_at <= ^end_dt and
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

    current_avg_hit_rate = avg_cache_hit_rate(project_id, start_date, end_date, opts)

    previous_start_date = Date.add(start_date, -days_delta)
    previous_avg_hit_rate = avg_cache_hit_rate(project_id, previous_start_date, start_date, opts)

    processed_data =
      process_hit_rate_data(current_data, start_date, end_date, date_period)

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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)

    current_period_percentile =
      cache_hit_rate_period_percentile(project_id, percentile, start_date, end_date, opts)

    previous_period_percentile =
      cache_hit_rate_period_percentile(
        project_id,
        percentile,
        Date.add(start_date, -days_delta),
        start_date,
        opts
      )

    time_bucket = time_bucket_for_date_period(date_period)
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_dt and
            b.inserted_at <= ^end_dt and
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

    processed_data = process_hit_rate_data(hit_rate_data, start_date, end_date, date_period)

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

  defp cache_hit_rate_period_percentile(project_id, percentile, start_date, end_date, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_dt and
            b.inserted_at <= ^end_dt and
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

  defp avg_cache_hit_rate(project_id, start_date, end_date, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_dt and
            b.inserted_at <= ^end_dt and
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

  defp process_hit_rate_data(hit_rate_data, start_date, end_date, date_period) do
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
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      hit_rate = Map.get(hit_rate_map, date, 0.0)
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
  def build_cache_hit_rate(project_id, start_date, end_date, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_dt and
            b.inserted_at <= ^end_dt and
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
  def build_cache_hit_rates(project_id, start_date, end_date, time_bucket, opts) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    pg_time_bucket = clickhouse_interval_to_postgrex_interval(time_bucket)

    query =
      from(b in Build,
        group_by: selected_as(:date_bucket),
        where:
          b.project_id == ^project_id and
            b.inserted_at >= ^start_dt and
            b.inserted_at <= ^end_dt and
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

  defp format_datetime_for_date_format(datetime, "%Y-%m-%d"), do: Date.to_string(DateTime.to_date(datetime))

  defp format_datetime_for_date_format(datetime, "%Y-%m"),
    do: "#{datetime.year}-#{String.pad_leading(to_string(datetime.month), 2, "0")}"

  defp format_datetime_for_date_format(datetime, _), do: Date.to_string(DateTime.to_date(datetime))

  defp get_clickhouse_date_format("1 day"), do: "%Y-%m-%d"
  defp get_clickhouse_date_format("1 month"), do: "%Y-%m"
  defp get_clickhouse_date_format(_), do: "%Y-%m-%d"

  defp clickhouse_interval_to_postgrex_interval("1 day"), do: %Interval{days: 1}
  defp clickhouse_interval_to_postgrex_interval("1 month"), do: %Interval{months: 1}

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
  Gets test run metrics for a specific test run.

  Returns a map with:
  - total_count: Total number of test cases
  - failed_count: Number of failed test cases
  - avg_duration: Average test case duration in milliseconds
  """
  def get_test_run_metrics(test_run_id) do
    alias Tuist.Runs.TestCaseRun

    query =
      from t in TestCaseRun,
        where: t.test_run_id == ^test_run_id,
        select: %{
          total_count: count(t.id),
          failed_count: fragment("countIf(? = 1)", t.status),
          avg_duration: avg(t.duration)
        }

    case ClickHouseRepo.one(query) do
      nil ->
        %{total_count: 0, failed_count: 0, avg_duration: 0}

      result ->
        %{
          total_count: result.total_count,
          failed_count: result.failed_count,
          avg_duration: if(is_nil(result.avg_duration), do: 0, else: round(result.avg_duration))
        }
    end
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
  def module_cache_hit_rate_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(Date.utc_today(), -30))
    end_date = Keyword.get(opts, :end_date, Date.utc_today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    # Get current period data
    hit_rate_result = CommandEvents.cache_hit_rate(project_id, start_date, end_date, opts)

    hit_rate_time_series =
      CommandEvents.cache_hit_rates(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    # Calculate current hit rate
    cacheable = hit_rate_result.cacheable_targets_count || 0
    local_hits = hit_rate_result.local_cache_hits_count || 0
    remote_hits = hit_rate_result.remote_cache_hits_count || 0
    total_hits = local_hits + remote_hits
    avg_hit_rate = calculate_hit_rate_percentage(total_hits, cacheable)

    # Calculate trend (compare with previous period)
    previous_start = Date.add(start_date, -days_delta)
    previous_result = CommandEvents.cache_hit_rate(project_id, previous_start, start_date, opts)
    previous_cacheable = previous_result.cacheable_targets_count || 0
    previous_hits = (previous_result.local_cache_hits_count || 0) + (previous_result.remote_cache_hits_count || 0)

    previous_hit_rate = calculate_hit_rate_percentage(previous_hits, previous_cacheable)

    hit_rate_trend = trend(previous_value: previous_hit_rate, current_value: avg_hit_rate)

    # Process hit rate time series
    hit_rate_dates = Enum.map(hit_rate_time_series, & &1.date)

    hit_rate_values =
      Enum.map(hit_rate_time_series, fn item ->
        cacheable = item.cacheable_targets || 0
        local = item.local_cache_target_hits || 0
        remote = item.remote_cache_target_hits || 0
        calculate_hit_rate_percentage(local + remote, cacheable)
      end)

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
    start_date = Keyword.get(opts, :start_date, Date.add(Date.utc_today(), -30))
    end_date = Keyword.get(opts, :end_date, Date.utc_today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    # Get current period data
    hit_rate_time_series =
      CommandEvents.cache_hit_rates(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    hit_rate_dates = Enum.map(hit_rate_time_series, & &1.date)

    hits_values =
      Enum.map(hit_rate_time_series, fn item ->
        (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
      end)

    total_hits_count = Enum.sum(hits_values)

    # Get previous period data for trend
    previous_start = Date.add(start_date, -days_delta)

    previous_hits_series =
      CommandEvents.cache_hit_rates(
        project_id,
        previous_start,
        start_date,
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
    start_date = Keyword.get(opts, :start_date, Date.add(Date.utc_today(), -30))
    end_date = Keyword.get(opts, :end_date, Date.utc_today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    # Get current period data
    hit_rate_time_series =
      CommandEvents.cache_hit_rates(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    hit_rate_dates = Enum.map(hit_rate_time_series, & &1.date)

    misses_values =
      Enum.map(hit_rate_time_series, fn item ->
        cacheable = item.cacheable_targets || 0
        hits = (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
        max(0, cacheable - hits)
      end)

    total_misses_count = Enum.sum(misses_values)

    # Get previous period data for trend
    previous_start = Date.add(start_date, -days_delta)

    previous_hits_series =
      CommandEvents.cache_hit_rates(
        project_id,
        previous_start,
        start_date,
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
    start_date = Keyword.get(opts, :start_date, Date.add(Date.utc_today(), -30))
    end_date = Keyword.get(opts, :end_date, Date.utc_today())

    days_delta = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    # Calculate current period percentile
    current_period_percentile =
      module_cache_hit_rate_period_percentile(project_id, percentile, start_date, end_date, opts)

    # Calculate previous period percentile for trend
    previous_start = Date.add(start_date, -days_delta)

    previous_period_percentile =
      module_cache_hit_rate_period_percentile(project_id, percentile, previous_start, start_date, opts)

    # Get percentile data over time
    percentile_time_series =
      CommandEvents.cache_hit_rate_percentiles(
        project_id,
        start_date,
        end_date,
        date_period,
        clickhouse_time_bucket,
        percentile,
        opts
      )

    percentile_dates = Enum.map(percentile_time_series, & &1.date)

    percentile_values =
      Enum.map(percentile_time_series, fn item ->
        if item.percentile_hit_rate, do: Float.round(item.percentile_hit_rate, 1), else: 0.0
      end)

    %{
      avg_hit_rate: current_period_percentile,
      trend: trend(previous_value: previous_period_percentile, current_value: current_period_percentile),
      dates: percentile_dates,
      values: percentile_values
    }
  end

  defp module_cache_hit_rate_period_percentile(project_id, percentile, start_date, end_date, opts) do
    result = CommandEvents.cache_hit_rate_period_percentile(project_id, start_date, end_date, percentile, opts)

    case result do
      nil -> 0.0
      value when is_float(value) -> Float.round(value, 1)
      value -> Float.round(value * 1.0, 1)
    end
  end
end
