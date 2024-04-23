defmodule TuistCloud.CommandEvents do
  @moduledoc ~S"""
  A module for operations related to command events.
  """
  alias TuistCloud.Repo
  alias TuistCloud.CommandEvents.Event
  alias TuistCloud.CommandEvents.DurationAverage
  alias TuistCloud.CommandEvents.CacheHitRateAverage
  alias TuistCloud.Time
  import Ecto.Query

  def get_command_duration_analytics(
        name,
        opts
      ) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    previous_total_average_duration =
      TuistCloud.CommandEvents.get_total_command_period_average_duration(
        name,
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date
      )

    total_average_duration =
      TuistCloud.CommandEvents.get_total_command_period_average_duration(
        name,
        project_id,
        start_date: start_date,
        end_date: end_date
      )

    average_durations =
      TuistCloud.CommandEvents.get_command_average(
        name,
        project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period
      )

    sorted_average_durations = Enum.sort(Map.values(average_durations), &(&1.date >= &2.date))

    %{
      trend:
        get_trend(
          previous_value: previous_total_average_duration,
          current_value: total_average_duration
        ),
      total_average_duration: total_average_duration,
      average_durations: average_durations,
      dates:
        get_formatted_dates(
          Enum.map(
            sorted_average_durations,
            & &1.date
          ),
          date_period
        ),
      values:
        Enum.map(
          sorted_average_durations,
          & &1.value
        )
    }
  end

  def get_command_runs_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))
    days_diff = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    previous_command_runs =
      get_command_runs(
        name,
        project_id: project_id,
        start_date: Date.add(start_date, -days_diff),
        end_date: start_date,
        date_period: date_period
      )

    command_runs =
      get_command_runs(
        name,
        project_id: project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period
      )

    runs_count = Enum.sum(Enum.map(command_runs, & &1.value))

    %{
      trend:
        get_trend(
          previous_value: Enum.sum(Enum.map(previous_command_runs, & &1.value)),
          current_value: runs_count
        ),
      runs_count: Enum.sum(Enum.map(command_runs, & &1.value)),
      values:
        Enum.map(
          command_runs,
          & &1.value
        ),
      dates:
        get_formatted_dates(
          Enum.map(
            command_runs,
            & &1.date
          ),
          date_period
        )
    }
  end

  defp get_command_runs(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))
    date_period = opts |> Keyword.get(:date_period)

    command_events =
      get_command_events(project_id, name: name, start_date: start_date, end_date: end_date)

    command_events_grouped =
      command_events_grouped_by_date(command_events, date_period: date_period)

    command_events_with_all_dates =
      Map.new(
        date_range_for_date_period(date_period, start_date: start_date, end_date: end_date),
        fn date ->
          command_event_average = command_events_grouped[date]

          case command_event_average do
            nil -> {date, %{date: date, value: 0}}
            runs -> {date, %{date: date, value: length(runs)}}
          end
        end
      )

    Enum.sort(
      Map.values(command_events_with_all_dates),
      &(&1.date >= &2.date)
    )
  end

  @doc """
  Returns the trend between the current value and the previous value as a percentage value. The value is negative if the current_value is smaller than previous_value.

  Returns 0 if the previous value is 0 or if the current value is 0.
  """
  def get_trend(opts) do
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

  def get_total_command_period_average_duration(
        name,
        project_id,
        opts \\ []
      ) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = opts |> Keyword.get(:end_date, DateTime.to_date(Time.utc_now()))

    command_events =
      get_command_events(project_id, name: name, start_date: start_date, end_date: end_date)

    if Enum.empty?(command_events) do
      0.0
    else
      Enum.sum(
        Enum.map(
          command_events,
          & &1.duration
        )
      ) / length(command_events)
    end
  end

  def get_command_average(
        name,
        project_id,
        opts \\ []
      ) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = opts |> Keyword.get(:end_date, DateTime.to_date(Time.utc_now()))
    date_period = opts |> Keyword.get(:date_period, :day)

    command_events =
      get_command_events(project_id, name: name, start_date: start_date, end_date: end_date)

    command_events_grouped =
      command_events_grouped_by_date(command_events, date_period: date_period)

    command_event_averages =
      Map.new(command_events_grouped, fn {date, events} ->
        {
          date,
          %DurationAverage{
            date: date,
            value: Enum.sum(Enum.map(events, & &1.duration)) / length(events),
            runs_count: length(events)
          }
        }
      end)

    Map.new(
      date_range_for_date_period(date_period, start_date: start_date, end_date: end_date),
      fn date ->
        command_event_average = command_event_averages[date]

        case command_event_average do
          nil -> {date, %DurationAverage{date: date, value: 0, runs_count: 0}}
          duration_average -> {date, duration_average}
        end
      end
    )
  end

  def get_cache_hit_rate_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(Time.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    current_cache_hit_rate =
      get_cache_hit_rate(
        project_id,
        start_date: start_date,
        end_date: end_date
      )

    previous_cache_hit_rate =
      get_cache_hit_rate(
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date
      )

    cache_hit_rates =
      get_cache_hit_rates(project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period
      )

    sorted_cache_hit_rates = Enum.sort(Map.values(cache_hit_rates), &(&1.date >= &2.date))

    %{
      trend:
        get_trend(
          previous_value: previous_cache_hit_rate,
          current_value: current_cache_hit_rate
        ),
      cache_hit_rate: current_cache_hit_rate,
      cache_hit_rates: cache_hit_rates,
      dates:
        get_formatted_dates(
          Enum.map(
            sorted_cache_hit_rates,
            & &1.date
          ),
          date_period
        ),
      values:
        Enum.map(
          sorted_cache_hit_rates,
          & &1.value
        )
    }
  end

  defp get_cache_hit_rates(project_id, opts) do
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)
    date_period = opts |> Keyword.get(:date_period)

    command_events = get_command_events(project_id, start_date: start_date, end_date: end_date)

    command_events_grouped =
      command_events_grouped_by_date(command_events, date_period: date_period)

    command_event_cache_hit_rates =
      Map.new(command_events_grouped, fn {date, events} ->
        {
          date,
          %CacheHitRateAverage{
            date: date,
            value: get_cache_hit_rate_for_command_events(events),
            runs_count: length(events)
          }
        }
      end)

    Map.new(
      Date.range(start_date, end_date)
      |> Enum.filter(fn date ->
        case date_period do
          :month ->
            date.day == 1

          :day ->
            true
        end
      end),
      fn date ->
        command_event_average = command_event_cache_hit_rates[date]

        case command_event_average do
          nil -> {date, %CacheHitRateAverage{date: date, value: 0, runs_count: 0}}
          cache_hit_rate -> {date, cache_hit_rate}
        end
      end
    )
  end

  defp get_cache_hit_rate(project_id, opts) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = DateTime.to_date(Time.utc_now())
    command_events = get_command_events(project_id, start_date: start_date, end_date: end_date)

    get_cache_hit_rate_for_command_events(command_events)
  end

  def create_command_event(%{
        name: name,
        duration: duration,
        tuist_version: tuist_version,
        project: %{id: project_id},
        cacheable_targets: cacheable_targets,
        local_cache_target_hits: local_cache_target_hits,
        remote_cache_target_hits: remote_cache_target_hits,
        created_at: created_at
      }) do
    %Event{}
    |> Event.create_changeset(%{
      name: name,
      duration: duration,
      tuist_version: tuist_version,
      project_id: project_id,
      cacheable_targets: cacheable_targets,
      local_cache_target_hits: local_cache_target_hits,
      remote_cache_target_hits: remote_cache_target_hits,
      created_at: created_at
    })
    |> Repo.insert!()
  end

  defp get_command_events(project_id, opts) do
    name = opts |> Keyword.get(:name)
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = opts |> Keyword.get(:end_date, DateTime.to_date(Time.utc_now()))

    command_events_query =
      from e in Event,
        join: p in assoc(e, :project),
        where:
          p.id == ^project_id and
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59])

    if is_nil(name) do
      Repo.all(command_events_query)
    else
      Repo.all(
        command_events_query
        |> where([e], e.name == ^name)
      )
    end
  end

  defp get_cache_hit_rate_for_command_events(command_events) do
    metadata =
      Enum.reduce(
        command_events,
        %{cacheable_targets: [], local_cache_target_hits: [], remote_cache_target_hits: []},
        fn event, acc ->
          cache_metadata = get_command_event_cache_metadata(event)

          %{
            cacheable_targets: acc.cacheable_targets ++ cache_metadata.cacheable_targets,
            local_cache_target_hits:
              acc.local_cache_target_hits ++ cache_metadata.local_cache_target_hits,
            remote_cache_target_hits:
              acc.remote_cache_target_hits ++ cache_metadata.remote_cache_target_hits
          }
        end
      )

    if Enum.empty?(metadata.cacheable_targets) do
      0
    else
      (length(metadata.local_cache_target_hits) +
         length(metadata.remote_cache_target_hits)) / length(metadata.cacheable_targets)
    end
  end

  defp get_command_event_cache_metadata(command_event) do
    %{
      cacheable_targets: String.split(command_event.cacheable_targets || "", ";", trim: true),
      local_cache_target_hits:
        String.split(command_event.local_cache_target_hits || "", ";", trim: true),
      remote_cache_target_hits:
        String.split(command_event.remote_cache_target_hits || "", ";", trim: true)
    }
  end

  defp command_events_grouped_by_date(command_events, opts) do
    date_period = opts |> Keyword.get(:date_period)

    Enum.group_by(command_events, fn e ->
      date = NaiveDateTime.to_date(e.created_at)

      case date_period do
        :month ->
          Date.new!(date.year, date.month, 1)

        :day ->
          date
      end
    end)
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

  defp get_formatted_dates(dates, date_period) do
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
end
