defmodule Tuist.Runners.GitLab.LogParser do
  @moduledoc "Converts GitLab section markers to timestamps without exposing control records in job logs."

  @section ~r/section_(?:start|end):(\d+):[^\r\n]*\r/

  def parse(lines, first_line_number, fallback_ts) do
    {rows, _} =
      lines
      |> Enum.with_index(first_line_number)
      |> Enum.map_reduce(fallback_ts, fn {line, number}, previous ->
        ts =
          case Regex.run(@section, line, capture: :all_but_first) do
            [seconds] ->
              case DateTime.from_unix(String.to_integer(seconds)) do
                {:ok, %{microsecond: {usec, _}} = time} -> %{time | microsecond: {usec, 6}}
                _ -> previous
              end

            _ ->
              previous
          end

        message = line |> String.replace(@section, "") |> String.trim_trailing("\r")
        {%{line_number: number, ts: ts, message: message}, ts}
      end)

    rows
  end
end
