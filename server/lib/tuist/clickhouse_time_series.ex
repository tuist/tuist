defmodule Tuist.ClickHouseTimeSeries do
  @moduledoc false

  def granularity(start_datetime, end_datetime) do
    duration_seconds = DateTime.diff(end_datetime, start_datetime, :second)

    cond do
      duration_seconds <= 2 * 24 * 60 * 60 -> :hour
      duration_seconds >= 60 * 24 * 60 * 60 -> :month
      true -> :day
    end
  end

  def date_format(:hour), do: "%Y-%m-%d %H:00"
  def date_format(:day), do: "%Y-%m-%d"
  def date_format(:month), do: "%Y-%m"

  def buckets(start_datetime, end_datetime, :hour) do
    %{start_datetime | minute: 0, second: 0, microsecond: {0, 0}}
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
    |> Enum.map(&Calendar.strftime(&1, date_format(:hour)))
  end

  def buckets(start_datetime, end_datetime, :day) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.map(&Date.to_iso8601/1)
  end

  def buckets(start_datetime, end_datetime, :month) do
    start_date = start_datetime |> DateTime.to_date() |> Date.beginning_of_month()
    end_date = end_datetime |> DateTime.to_date() |> Date.beginning_of_month()

    start_date
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, end_date) != :gt))
    |> Enum.map(&Calendar.strftime(&1, date_format(:month)))
  end
end
