defmodule Tuist.Runs.Analytics do
  @moduledoc """
  Module for run-related analytics, such as builds.
  """
  alias Tuist.Runs.Build
  alias Tuist.Repo
  alias Tuist.CommandEvents.Event
  import Ecto.Query
  import Timescale.Hyperfunctions

  def builds_analytics(project_id, opts) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.utc_now() |> DateTime.to_date())

    runs_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date, date_period, time_bucket ->
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
      end
    })
  end

  def builds_duration_analytics(
        project_id,
        opts \\ []
      ) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    runs_duration_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date ->
        from(b in Build,
          where:
            b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
              b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
              b.project_id == ^project_id
        )
        |> add_filters(opts)
      end,
      average_durations: fn start_date, end_date, date_period, time_bucket ->
        from(b in Build,
          group_by: selected_as(^date_period),
          where:
            b.inserted_at > ^DateTime.new!(start_date, ~T[00:00:00]) and
              b.inserted_at < ^DateTime.new!(end_date, ~T[23:59:59]) and
              b.project_id == ^project_id,
          select: %{
            date: selected_as(time_bucket(b.inserted_at, ^time_bucket), ^date_period),
            average: avg(b.duration)
          }
        )
        |> add_filters(opts)
      end
    })
  end

  def runs_duration_analytics(
        name,
        opts
      ) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))

    runs_duration_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date ->
        from(e in Event,
          where:
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
              e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
              e.project_id == ^project_id
        )
        |> add_filters(opts)
      end,
      average_durations: fn start_date, end_date, date_period, time_bucket ->
        from(e in Event,
          group_by: selected_as(^date_period),
          where:
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
              e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
              e.project_id == ^project_id,
          select: %{
            date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
            average: avg(e.duration)
          }
        )
        |> add_filters(opts)
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
      runs_duration_average_per_period(%{
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
        formatted_dates(
          Enum.map(
            average_durations,
            & &1.date
          ),
          date_period
        ),
      values:
        Enum.map(
          average_durations,
          & &1.average
        )
    }
  end

  # Returns analytics for number of runs, such as runs or builds.
  defp runs_analytics(%{
         start_date: start_date,
         end_date: end_date,
         runs: runs
       }) do
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
        formatted_dates(
          Enum.map(
            current_runs,
            & &1.date
          ),
          date_period
        )
    }
  end

  def runs_analytics(project_id, name, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.utc_now() |> DateTime.to_date())

    runs_analytics(%{
      start_date: start_date,
      end_date: end_date,
      runs: fn start_date, end_date, date_period, time_bucket ->
        from(e in Event,
          group_by: selected_as(^date_period),
          where:
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
              e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
              e.project_id == ^project_id,
          select: %{
            date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
            count: count(e)
          }
        )
      end
    })
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
        formatted_dates(
          Enum.map(
            cache_hit_rates,
            & &1.date
          ),
          date_period
        ),
      values:
        Enum.map(
          cache_hit_rates,
          & &1.cache_hit_rate
        )
    }
  end

  defp cache_hit_rate(project_id, opts) do
    start_date = opts |> Keyword.get(:start_date, Date.add(DateTime.utc_now(), -30))
    end_date = DateTime.to_date(DateTime.utc_now())

    result =
      from(e in Event,
        where:
          e.project_id == ^project_id and
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]),
        select: %{
          cacheable_targets_count: sum(fragment("array_length(?, 1)", e.cacheable_targets)),
          local_cache_target_hits_count:
            sum(fragment("array_length(?, 1)", e.local_cache_target_hits)),
          remote_cache_target_hits_count:
            sum(fragment("array_length(?, 1)", e.remote_cache_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.one()

    local_cache_target_hits_count = result.local_cache_target_hits_count || 0
    remote_cache_target_hits_count = result.remote_cache_target_hits_count || 0
    cacheable_targets_count = result.cacheable_targets_count || 0

    if cacheable_targets_count == 0 do
      0
    else
      (local_cache_target_hits_count + remote_cache_target_hits_count) / cacheable_targets_count
    end
  end

  defp cache_hit_rates(project_id, opts) do
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)
    date_period = opts |> Keyword.get(:date_period)

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
          remote_cache_target_hits:
            sum(fragment("array_length(?, 1)", e.remote_cache_target_hits))
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

    date_range_for_date_period(date_period, start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      cache_hit_rate_metadata = Map.get(cache_hit_rate_metadata_map, date)

      if is_nil(cache_hit_rate_metadata) or (cache_hit_rate_metadata.cacheable_targets || 0) == 0 do
        %{
          date: date,
          cache_hit_rate: 0
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

  def total_execution_period_average_duration(%{
        query: query,
        start_date: start_date,
        end_date: end_date
      }) do
    average =
      query.(start_date, end_date)
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
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)
    days_delta = Date.diff(end_date, start_date)

    if days_delta >= 60 do
      :month
    else
      :day
    end
  end

  defp formatted_dates(dates, date_period) do
    Enum.map(
      dates,
      case date_period do
        :month ->
          &Calendar.strftime(&1, "%b %Y")

        :day ->
          &Calendar.strftime(&1, "%b %d")
      end
    )
  end

  defp time_bucket_for_date_period(date_period) do
    case date_period do
      :day -> %Postgrex.Interval{days: 1}
      :month -> %Postgrex.Interval{months: 1}
    end
  end

  defp runs_duration_average_per_period(%{
         query: query,
         start_date: start_date,
         end_date: end_date,
         date_period: date_period,
         time_bucket: time_bucket
       }) do
    averages =
      query.(start_date, end_date, date_period, time_bucket)
      |> Repo.all()
      |> Map.new(&{normalise_date(&1.date, date_period), &1.average})

    date_range_for_date_period(date_period, start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      average = Map.get(averages, date)

      %{
        date: date,
        average:
          if is_nil(average) do
            0
          else
            Decimal.to_float(average)
          end
      }
    end)
  end

  defp add_filters(query, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    case is_ci do
      nil -> query
      true -> where(query, [e], e.is_ci == true)
      false -> where(query, [e], e.is_ci == false)
    end
  end

  defp date_range_for_date_period(date_period, opts) do
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)

    Date.range(start_date, end_date)
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

  defp runs_per_period(%{
         query: query,
         start_date: start_date,
         end_date: end_date,
         date_period: date_period
       }) do
    runs =
      query.(start_date, end_date, date_period, time_bucket_for_date_period(date_period))
      |> Repo.all()
      |> Map.new(&{normalise_date(&1.date, date_period), &1.count})

    date_range_for_date_period(date_period, start_date: start_date, end_date: end_date)
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
