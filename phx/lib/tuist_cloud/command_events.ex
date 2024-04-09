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

  @doc """
  Returns the trend between the current value and the previous value as a percentage value. The value is negative if the current_value is smaller than previous_value.

  Returns 0 if the previous value is 0 or if the current value is 0.
  """
  def get_trend(
    opts
  ) do
    previous_value = Keyword.get(opts, :previous_value)
    current_value = Keyword.get(opts, :current_value)
    case {previous_value, current_value} do
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
      ) / 1000 / length(command_events)
    end
  end

  def get_command_average(
        name,
        project_id,
        opts \\ []
      ) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = opts |> Keyword.get(:end_date, DateTime.to_date(Time.utc_now()))

    command_events =
      get_command_events(project_id, name: name, start_date: start_date, end_date: end_date)

    command_events_grouped =
      command_events_grouped_by_date(command_events, start_date: start_date, end_date: end_date)

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
      Date.range(start_date, end_date),
      fn date ->
        command_event_average = command_event_averages[date]

        case command_event_average do
          nil -> {date, %DurationAverage{date: date, value: 0, runs_count: 0}}
          duration_average -> {date, duration_average}
        end
      end
    )
  end

  def get_cache_hit_rates(project_id, opts \\ []) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = DateTime.to_date(Time.utc_now())
    command_events = get_command_events(project_id, start_date: start_date, end_date: end_date)

    command_events_grouped =
      command_events_grouped_by_date(command_events, start_date: start_date, end_date: end_date)

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
      Date.range(start_date, end_date),
      fn date ->
        command_event_average = command_event_cache_hit_rates[date]

        case command_event_average do
          nil -> {date, %CacheHitRateAverage{date: date, value: 0, runs_count: 0}}
          cache_hit_rate -> {date, cache_hit_rate}
        end
      end
    )
  end

  def get_cache_hit_rate(project_id, opts \\ []) do
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
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)

    Enum.group_by(command_events, fn e ->
      date = NaiveDateTime.to_date(e.created_at)

      if Date.diff(end_date, start_date) >= 365 do
        date.month
      else
        date
      end

      NaiveDateTime.to_date(e.created_at)
    end)
  end
end
