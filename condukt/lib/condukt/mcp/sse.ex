defmodule Condukt.MCP.SSE do
  @moduledoc false

  # Minimal Server-Sent Events parser used by the HTTP+SSE and
  # Streamable HTTP transports. Accumulates raw chunks and yields
  # complete events (`%{event: type, data: payload}`).
  #
  # The parser only implements the subset of SSE that MCP relies on:
  # `event:` and `data:` fields, terminated by an empty line. `id:`,
  # `retry:`, and comments are ignored.

  @doc "Returns an empty parser state."
  def new, do: %{buffer: "", current_event: nil, current_data: []}

  @doc """
  Feeds a chunk into the parser, returning `{events, new_state}`.

  Each event in the returned list is `%{event: binary | nil, data: binary}`.
  """
  def feed(state, chunk) when is_binary(chunk) do
    buffer = state.buffer <> chunk
    {lines, rest} = take_complete_lines(buffer)
    {events, current_event, current_data} = process_lines(lines, state.current_event, state.current_data, [])
    {events, %{buffer: rest, current_event: current_event, current_data: current_data}}
  end

  @doc "Flushes any complete event held in the parser buffer."
  def flush(state) do
    if state.current_data == [] and is_nil(state.current_event) do
      {[], state}
    else
      data = state.current_data |> Enum.reverse() |> Enum.join("\n")
      event = %{event: state.current_event, data: data}
      {[event], %{state | current_event: nil, current_data: []}}
    end
  end

  defp take_complete_lines(buffer) do
    case :binary.split(buffer, "\n", [:global]) do
      [single] -> {[], single}
      parts -> finalize_split(Enum.split(parts, length(parts) - 1))
    end
  end

  defp finalize_split({lines, [trailing]}) do
    lines = Enum.map(lines, &trim_carriage_return/1)
    {lines, trailing}
  end

  defp trim_carriage_return(line) do
    if String.ends_with?(line, "\r"), do: String.slice(line, 0..-2//1), else: line
  end

  defp process_lines([], current_event, current_data, events) do
    {Enum.reverse(events), current_event, current_data}
  end

  defp process_lines(["" | rest], current_event, current_data, events) do
    if current_data == [] and is_nil(current_event) do
      process_lines(rest, nil, [], events)
    else
      data = current_data |> Enum.reverse() |> Enum.join("\n")
      event = %{event: current_event, data: data}
      process_lines(rest, nil, [], [event | events])
    end
  end

  defp process_lines([":" <> _comment | rest], current_event, current_data, events) do
    process_lines(rest, current_event, current_data, events)
  end

  defp process_lines([line | rest], current_event, current_data, events) do
    case parse_field(line) do
      {:event, value} -> process_lines(rest, value, current_data, events)
      {:data, value} -> process_lines(rest, current_event, [value | current_data], events)
      :ignore -> process_lines(rest, current_event, current_data, events)
    end
  end

  defp parse_field(line) do
    case String.split(line, ":", parts: 2) do
      ["event", value] -> {:event, String.trim_leading(value, " ")}
      ["data", value] -> {:data, String.trim_leading(value, " ")}
      [_field, _value] -> :ignore
      _ -> :ignore
    end
  end
end
