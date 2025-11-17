defmodule Tuist.Utilities.DateFormatter do
  @moduledoc false
  def from_now(date) do
    case date |> Timex.from_now() |> String.split(" ") do
      [number, "month", relative] -> number <> "mo " <> relative
      [number, "months", relative] -> number <> "mo " <> relative
      [number, unit, relative] -> number <> String.at(unit, 0) <> " " <> relative
      _ -> Timex.from_now(date)
    end
  end

  def format_duration_from_seconds(duration_ms, opts \\ []) do
    format_duration_from_milliseconds(duration_ms * 1000, opts)
  end

  def format_duration_from_milliseconds(duration_ms, opts \\ []) do
    include_seconds = Keyword.get(opts, :include_seconds, true)
    duration_ms = trunc(duration_ms)

    cond do
      duration_ms == 0 ->
        "0.0s"

      duration_ms < 1000 ->
        "#{duration_ms}ms"

      true ->
        hours = div(duration_ms, 3_600_000)
        remainder = rem(duration_ms, 3_600_000)

        minutes = div(remainder, 60_000)
        remainder = rem(remainder, 60_000)

        seconds = div(remainder, 1_000)
        milliseconds = rem(remainder, 1_000)

        seconds_with_ms = seconds + milliseconds / 1000

        parts = []
        parts = if hours > 0, do: parts ++ ["#{hours}h"], else: parts
        parts = if minutes > 0, do: parts ++ ["#{minutes}m"], else: parts

        parts =
          cond do
            hours > 0 and seconds > 0 and not include_seconds ->
              # For times over 1 hour, don't include seconds only if include_seconds is false
              parts

            duration_ms > 60_000 and seconds > 0 ->
              parts ++ ["#{seconds}s"]

            true ->
              parts ++ ["#{Float.round(seconds_with_ms, 1)}s"]
          end

        Enum.join(parts, " ")
    end
  end

  def format_duration_based_on_max(duration_ms, max_duration_ms) do
    cond do
      duration_ms == 0 ->
        if max_duration_ms < 3_600_000, do: "0m", else: "0h"

      max_duration_ms < 3_600_000 ->
        # Show in minutes when max is less than 1 hour
        minutes = div(trunc(duration_ms), 60_000)
        remainder = rem(trunc(duration_ms), 60_000)
        seconds = div(remainder, 1_000)

        if minutes > 0 and seconds > 30 do
          "#{minutes + 1}m"
        else
          "#{max(minutes, 1)}m"
        end

      true ->
        # Show in hours when max is 1 hour or more
        hours = div(trunc(duration_ms), 3_600_000)
        remainder = rem(trunc(duration_ms), 3_600_000)
        minutes = div(remainder, 60_000)

        if hours > 0 and minutes > 30 do
          "#{hours + 1}h"
        else
          "#{max(hours, 1)}h"
        end
    end
  end

  def format_hours_only(duration_seconds) do
    hours = Float.round(duration_seconds / 3600, 1)
    "#{hours}h"
  end

  @doc "Format datetime with day of week (Mon 15 Jan 14:30:25)"
  def format_full(%DateTime{} = datetime) do
    Timex.format!(datetime, "{WDshort} {D} {Mshort} {h24}:{m}:{s}")
  end

  def format_full(_), do: "Unknown"

  @doc "Format datetime in ISO-like format (2024-01-15 14:30:25 UTC)"
  def format_iso(%DateTime{} = datetime) do
    datetime = DateTime.truncate(datetime, :second)

    "#{datetime.year}-#{String.pad_leading(to_string(datetime.month), 2, "0")}-#{String.pad_leading(to_string(datetime.day), 2, "0")} #{String.pad_leading(to_string(datetime.hour), 2, "0")}:#{String.pad_leading(to_string(datetime.minute), 2, "0")}:#{String.pad_leading(to_string(datetime.second), 2, "0")} UTC"
  end

  def format_iso(_), do: "Unknown"

  @doc """
  Format datetime with timezone conversion.

  Takes a UTC datetime and converts it to the specified timezone.
  Falls back to UTC display if timezone is nil or conversion fails.

  ## Examples

      iex> DateFormatter.format_with_timezone(~U[2024-01-15 14:30:25Z], "America/New_York")
      "Mon 15 Jan 09:30:25 EST"

      iex> DateFormatter.format_with_timezone(~U[2024-01-15 14:30:25Z], nil)
      "Mon 15 Jan 14:30:25 UTC"
  """
  def format_with_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    local_time = Timex.Timezone.convert(datetime, timezone)
    Timex.format!(local_time, "{WDshort} {D} {Mshort} {h24}:{m}:{s}")
  rescue
    _ ->
      # Fallback to UTC if timezone conversion fails
      Timex.format!(datetime, "{WDshort} {D} {Mshort} {h24}:{m}:{s}") <> " UTC"
  end

  def format_with_timezone(%NaiveDateTime{} = naive_datetime, timezone) when is_binary(timezone) do
    # Convert NaiveDateTime to DateTime assuming UTC, then convert to timezone
    utc_datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")
    local_time = Timex.Timezone.convert(utc_datetime, timezone)
    Timex.format!(local_time, "{WDshort} {D} {Mshort} {h24}:{m}:{s}")
  rescue
    _ ->
      # Fallback to UTC if timezone conversion fails
      Timex.format!(naive_datetime, "{WDshort} {D} {Mshort} {h24}:{m}:{s}") <> " UTC"
  end

  def format_with_timezone(%DateTime{} = datetime, _timezone) do
    # Fallback when no timezone is available
    Timex.format!(datetime, "{WDshort} {D} {Mshort} {h24}:{m}:{s}") <> " UTC"
  end

  def format_with_timezone(%NaiveDateTime{} = naive_datetime, _timezone) do
    # Fallback when no timezone is available
    Timex.format!(naive_datetime, "{WDshort} {D} {Mshort} {h24}:{m}:{s}") <> " UTC"
  end

  def format_with_timezone(_datetime, _timezone) do
    # Fallback for other types
    "Unknown"
  end
end
