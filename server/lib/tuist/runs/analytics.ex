defmodule Tuist.Runs.Analytics do
  @moduledoc """
  Module for general command events analytics (runs).
  This module provides analytics for CLI command invocations like "generate", "build", "test", etc.
  """

  alias Postgrex.Interval
  alias Tuist.CommandEvents

  def runs_analytics(project_id, name, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_runs_data =
      CommandEvents.run_count(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        name,
        opts
      )

    current_runs = process_runs_count_data(current_runs_data, start_datetime, end_datetime, date_period)

    previous_runs_count =
      runs_total_count(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, name, opts)

    current_runs_count = runs_total_count(project_id, start_datetime, end_datetime, name, opts)

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

  defp runs_total_count(project_id, start_datetime, end_datetime, name, opts) do
    CommandEvents.run_analytics(
      project_id,
      start_datetime,
      end_datetime,
      Keyword.put(opts, :name, name)
    )[:count] || 0
  end

  def runs_duration_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    previous_period_runs_aggregated_analytics =
      CommandEvents.run_analytics(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        Keyword.put(opts, :name, name)
      )

    previous_period_total_average_duration =
      previous_period_runs_aggregated_analytics[:average_duration] || 0

    current_period_runs_data =
      CommandEvents.run_analytics(
        project_id,
        start_datetime,
        end_datetime,
        Keyword.put(opts, :name, name)
      )

    total_average_duration = current_period_runs_data[:average_duration] || 0

    average_durations_data =
      CommandEvents.run_average_durations(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        name,
        opts
      )

    average_durations =
      process_durations_data(average_durations_data, start_datetime, end_datetime, date_period)

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

  @doc """
  Returns the trend between the current value and the previous value as a percentage value.
  The value is negative if the current_value is smaller than previous_value.

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

  defp process_runs_count_data(runs_data, start_datetime, end_datetime, date_period) do
    runs_map =
      case runs_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.count})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      count = Map.get(runs_map, normalized_date, 0)
      %{date: date, count: count}
    end)
  end
end
