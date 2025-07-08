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

  def format_duration_from_milliseconds(duration_ms) do
    cond do
      duration_ms == 0 ->
        "0.0s"

      duration_ms < 1000 ->
        "#{duration_ms}ms"

      true ->
        duration_ms = trunc(duration_ms)
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
          if duration_ms > 60_000 and seconds > 0,
            do: parts ++ ["#{seconds}s"],
            else: parts ++ ["#{Float.round(seconds_with_ms, 1)}s"]

        Enum.join(parts, " ")
    end
  end
end
