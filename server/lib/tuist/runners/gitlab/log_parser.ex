defmodule Tuist.Runners.GitLab.LogParser do
  @moduledoc "Converts GitLab section markers to timestamps without exposing control records in job logs."

  @section ~r/section_(?:start|end):(\d+):[^\r\n]*\r/
  @stream_line ~r/^(?:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z) )?[0-9a-fA-F]{2}[OE][ +](.*)$/s
  @erase_line ~r/\x1b\[[0-9;]*K/

  def parse(lines, first_line_number, fallback_ts) do
    {rows, _} =
      lines
      |> Enum.with_index(first_line_number)
      |> Enum.map_reduce(fallback_ts, fn {line, number}, previous ->
        {line, ts} = parse_stream(line, previous)
        message = line |> String.replace(@section, "") |> String.replace(@erase_line, "") |> String.trim_trailing("\r")
        {%{line_number: number, ts: ts, message: message}, ts}
      end)

    rows
  end

  defp parse_stream(line, previous) do
    case Regex.run(@stream_line, line, capture: :all_but_first) do
      [timestamp, message] ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, time, _} -> {message, with_precision(time)}
          _ -> {message, section_timestamp(message, previous)}
        end

      _ ->
        {line, section_timestamp(line, previous)}
    end
  end

  defp section_timestamp(line, previous) do
    with [seconds] <- Regex.run(@section, line, capture: :all_but_first),
         {:ok, time} <- DateTime.from_unix(String.to_integer(seconds)) do
      with_precision(time)
    else
      _ -> previous
    end
  end

  defp with_precision(%DateTime{microsecond: {usec, _}} = time), do: %{time | microsecond: {usec, 6}}
end
