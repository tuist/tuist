defmodule Tuist.Runs.Analytics do
  @moduledoc """
  Module for run-related analytics, such as builds.
  """
  import Ecto.Query
  import Timescale.Hyperfunctions

  alias Tuist.CommandEvents.Event
  alias Tuist.Repo
  alias Tuist.Runs.Build

  def builds_duration_analytics_grouped_by_category(project_id, category, opts \\ []) do
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

  def builds_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    runs_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date, date_period, time_bucket ->
        add_filters(
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
          ),
          opts
        )
      end
    })
  end

  def builds_duration_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    runs_duration_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date ->
        add_filters(
          from(b in Build,
            where:
              b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
                b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and b.project_id == ^project_id
          ),
          opts
        )
      end,
      average_durations: fn start_date, end_date, date_period, time_bucket ->
        add_filters(
          from(b in Build,
            group_by: selected_as(^date_period),
            where:
              b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
                b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and b.project_id == ^project_id,
            select: %{date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period), value: avg(b.duration)}
          ),
          opts
        )
      end
    })
  end

  def builds_percentile_durations(project_id, percentile, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    durations = fn start_date, end_date, date_period, time_bucket ->
      add_filters(
        from(b in Build,
          group_by: selected_as(^date_period),
          where:
            b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
              b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and b.project_id == ^project_id,
          select: %{
            date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
            value: fragment("percentile_cont(?) within group (order by ?)", ^percentile, b.duration)
          }
        ),
        opts
      )
    end

    # Group builds by period for trend analysis
    date_period = date_period(start_date: start_date, end_date: end_date)

    durations =
      runs_duration_per_period(%{
        query: durations,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period,
        time_bucket: time_bucket_for_date_period(date_period)
      })

    %{
      dates:
        Enum.map(
          durations,
          & &1.date
        ),
      values:
        Enum.map(
          durations,
          & &1.value
        )
    }
  end

  def runs_duration_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    runs_duration_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date ->
        add_filters(
          from(e in Event,
            where:
              e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
                e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
                e.project_id == ^project_id
          ),
          Keyword.put(opts, :name, name)
        )
      end,
      average_durations: fn start_date, end_date, date_period, time_bucket ->
        add_filters(
          from(e in Event,
            group_by: selected_as(^date_period),
            where:
              e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
                e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
                e.project_id == ^project_id,
            select: %{date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period), value: avg(e.duration)}
          ),
          Keyword.put(opts, :name, name)
        )
      end
    })
  end

  # Returns analytics for duration of runs, such as runs or builds.
  defp runs_duration_analytics(%{
         start_date: start_date,
         end_date: end_date,
         runs: runs,
         average_durations: average_durations
       }) do
    days_diff = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)

    previous_total_average_duration =
      total_execution_period_average_duration(%{
        query: runs,
        start_date: Date.add(start_date, -days_diff),
        end_date: start_date
      })

    total_average_duration =
      total_execution_period_average_duration(%{
        query: runs,
        start_date: start_date,
        end_date: end_date
      })

    average_durations =
      runs_duration_per_period(%{
        query: average_durations,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period,
        time_bucket: time_bucket_for_date_period(date_period)
      })

    %{
      trend:
        trend(
          previous_value: previous_total_average_duration,
          current_value: total_average_duration
        ),
      total_average_duration: total_average_duration,
      average_durations: average_durations,
      dates:
        Enum.map(
          average_durations,
          & &1.date
        ),
      values:
        Enum.map(
          average_durations,
          & &1.value
        )
    }
  end

  # Returns analytics for number of runs, such as runs or builds.
  defp runs_analytics(%{start_date: start_date, end_date: end_date, runs: runs}) do
    days_diff = Date.diff(end_date, start_date)
    date_period = date_period(start_date: start_date, end_date: end_date)

    previous_runs =
      runs_per_period(%{
        query: runs,
        start_date: Date.add(start_date, -days_diff),
        end_date: start_date,
        date_period: date_period
      })

    current_runs =
      runs_per_period(%{
        query: runs,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period
      })

    runs_count = Enum.sum(Enum.map(current_runs, & &1.count))

    %{
      trend:
        trend(
          previous_value: Enum.sum(Enum.map(previous_runs, & &1.count)),
          current_value: runs_count
        ),
      count: runs_count,
      values:
        Enum.map(
          current_runs,
          & &1.count
        ),
      dates:
        Enum.map(
          current_runs,
          & &1.date
        )
    }
  end

  def runs_analytics(project_id, name, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    runs_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date, date_period, time_bucket ->
        add_filters(
          from(e in Event,
            group_by: selected_as(^date_period),
            where:
              e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
                e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
                e.project_id == ^project_id,
            select: %{date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period), count: count(e)}
          ),
          Keyword.put(opts, :name, name)
        )
      end
    })
  end

  def builds_success_rate_analytics(project_id, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    current_success_rate =
      builds_success_rate(
        project_id,
        start_date: start_date,
        end_date: end_date,
        opts: opts
      )

    previous_success_rate =
      builds_success_rate(
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date,
        opts: opts
      )

    success_rates =
      builds_success_rates_per_period(project_id,
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

  defp builds_success_rate(project_id, opts) do
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

  defp builds_success_rates_per_period(project_id, opts) do
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

    result =
      from(e in Event,
        where:
          e.project_id == ^project_id and
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]),
        select: %{
          cacheable_targets_count: sum(fragment("array_length(?, 1)", e.cacheable_targets)),
          local_cache_target_hits_count: sum(fragment("array_length(?, 1)", e.local_cache_target_hits)),
          remote_cache_target_hits_count: sum(fragment("array_length(?, 1)", e.remote_cache_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.one()

    local_cache_target_hits_count = result.local_cache_target_hits_count || 0
    remote_cache_target_hits_count = result.remote_cache_target_hits_count || 0
    cacheable_targets_count = result.cacheable_targets_count || 0

    if cacheable_targets_count == 0 do
      0.0
    else
      (local_cache_target_hits_count + remote_cache_target_hits_count) / cacheable_targets_count
    end
  end

  defp cache_hit_rates(project_id, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)

    cache_hit_rate_metadata_map =
      from(e in Event,
        group_by: selected_as(^date_period),
        where:
          e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
            e.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
          cacheable_targets: sum(fragment("array_length(?, 1)", e.cacheable_targets)),
          local_cache_target_hits: sum(fragment("array_length(?, 1)", e.local_cache_target_hits)),
          remote_cache_target_hits: sum(fragment("array_length(?, 1)", e.remote_cache_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.all()
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
      from(e in Event,
        where:
          e.project_id == ^project_id and
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]),
        select: %{
          test_targets_count: sum(fragment("array_length(?, 1)", e.test_targets)),
          local_test_target_hits_count: sum(fragment("array_length(?, 1)", e.local_test_target_hits)),
          remote_test_target_hits_count: sum(fragment("array_length(?, 1)", e.remote_test_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.one()

    local_test_target_hits_count = result.local_test_target_hits_count || 0
    remote_test_target_hits_count = result.remote_test_target_hits_count || 0
    test_targets_count = result.test_targets_count || 0

    if test_targets_count == 0 do
      0.0
    else
      (local_test_target_hits_count + remote_test_target_hits_count) / test_targets_count
    end
  end

  defp selective_testing_hit_rates(project_id, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    date_period = Keyword.get(opts, :date_period)

    time_bucket = time_bucket_for_date_period(date_period)

    selective_testing_hit_rate_metadata_map =
      from(e in Event,
        group_by: selected_as(^date_period),
        where:
          e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
            e.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
          test_targets: sum(fragment("array_length(?, 1)", e.test_targets)),
          local_test_target_hits: sum(fragment("array_length(?, 1)", e.local_test_target_hits)),
          remote_test_target_hits: sum(fragment("array_length(?, 1)", e.remote_test_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.all()
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

  def total_execution_period_average_duration(%{query: query, start_date: start_date, end_date: end_date}) do
    average =
      start_date
      |> query.(end_date)
      |> Repo.aggregate(:avg, :duration)

    if is_nil(average) do
      0
    else
      Decimal.to_float(average)
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
      :day -> %Postgrex.Interval{days: 1}
      :month -> %Postgrex.Interval{months: 1}
    end
  end

  defp runs_duration_per_period(%{
         query: query,
         start_date: start_date,
         end_date: end_date,
         date_period: date_period,
         time_bucket: time_bucket
       }) do
    durations =
      start_date
      |> query.(end_date, date_period, time_bucket)
      |> Repo.all()
      |> Map.new(&{normalise_date(&1.date, date_period), &1.value})

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      duration = Map.get(durations, date)

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

  defp add_filters(query, opts) do
    query = query_with_is_ci_filter(query, opts)

    scheme = Keyword.get(opts, :scheme)

    query =
      case scheme do
        nil -> query
        _ -> where(query, [e], e.scheme == ^scheme)
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
          (e.name == "xcodebuild" and (e.subcommand == "test" or e.subcommand == "test-without-building")) or
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

  defp normalise_date(naive_datetime, date_period) do
    date = NaiveDateTime.to_date(naive_datetime)

    case date_period do
      :day -> date
      :month -> Date.beginning_of_month(date)
    end
  end

  defp runs_per_period(%{query: query, start_date: start_date, end_date: end_date, date_period: date_period}) do
    runs =
      start_date
      |> query.(end_date, date_period, time_bucket_for_date_period(date_period))
      |> Repo.all()
      |> Map.new(&{normalise_date(&1.date, date_period), &1.count})

    date_period
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      count = Map.get(runs, date)

      %{
        date: date,
        count:
          if is_nil(count) do
            0
          else
            count
          end
      }
    end)
  end
end
