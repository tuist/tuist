defmodule Condukt.Tools.Truncate do
  @moduledoc false
  # Output limits shared by the built-in tools, after pi's coding agent
  # (`packages/coding-agent/src/core/tools/truncate.ts` in badlogic/pi-mono,
  # MIT). Two limits apply, whichever is hit first: lines and UTF-8 bytes.
  # Lines are counted as `String.split(text, "\n")` does, without a trailing
  # empty line.

  @max_lines 2000
  @max_bytes 50 * 1024
  @max_line_chars 500

  def max_lines, do: @max_lines
  def max_bytes, do: @max_bytes
  def max_line_chars, do: @max_line_chars

  @doc """
  Keeps the first whole lines of `content` that fit both limits. Returns the
  kept text, whether anything was cut and by which limit, the line counts,
  and whether the first line alone exceeds the byte limit, in which case the
  text is empty.
  """
  def head(content, opts \\ []) do
    max_lines = Keyword.get(opts, :max_lines, @max_lines)
    max_bytes = Keyword.get(opts, :max_bytes, @max_bytes)
    lines = lines(content)
    total_lines = length(lines)

    result = %{
      content: content,
      truncated: false,
      truncated_by: nil,
      total_lines: total_lines,
      output_lines: total_lines,
      first_line_exceeds_limit: false
    }

    cond do
      total_lines <= max_lines and byte_size(content) <= max_bytes ->
        result

      byte_size(hd(lines)) > max_bytes ->
        %{result | content: "", truncated: true, truncated_by: :bytes, output_lines: 0, first_line_exceeds_limit: true}

      true ->
        {kept, by} = take_lines(lines, max_lines, max_bytes)
        %{result | content: Enum.join(kept, "\n"), truncated: true, truncated_by: by, output_lines: length(kept)}
    end
  end

  defp take_lines(lines, max_lines, max_bytes) do
    if(max_lines == :infinity, do: lines, else: Enum.take(lines, max_lines))
    |> Enum.reduce_while({[], 0}, fn line, {kept, bytes} ->
      bytes = bytes + byte_size(line) + if(kept == [], do: 0, else: 1)
      if bytes > max_bytes, do: {:halt, {kept, :bytes}}, else: {:cont, {[line | kept], bytes}}
    end)
    |> case do
      {kept, :bytes} -> {Enum.reverse(kept), :bytes}
      {kept, _bytes} -> {Enum.reverse(kept), :lines}
    end
  end

  defp lines(""), do: []

  defp lines(content) do
    lines = String.split(content, "\n")
    if String.ends_with?(content, "\n"), do: Enum.drop(lines, -1), else: lines
  end

  @doc "Cuts a line to `max_chars` characters, marking the cut."
  def line(text, max_chars \\ @max_line_chars) do
    if String.length(text) <= max_chars,
      do: {text, false},
      else: {String.slice(text, 0, max_chars) <> "... [truncated]", true}
  end

  @doc "A byte count as `512B`, `1.5KB`, or `2.0MB`."
  def format_size(bytes) when bytes < 1024, do: "#{bytes}B"
  def format_size(bytes) when bytes < 1024 * 1024, do: :erlang.float_to_binary(bytes / 1024, decimals: 1) <> "KB"
  def format_size(bytes), do: :erlang.float_to_binary(bytes / (1024 * 1024), decimals: 1) <> "MB"

  @doc """
  Appends `[notice. notice]` to `text`, as pi does, for the notices that are
  not `false` or `nil`.
  """
  def with_notices(text, notices) do
    case Enum.filter(notices, & &1) do
      [] -> text
      notices -> text <> "\n\n[" <> Enum.join(notices, ". ") <> "]"
    end
  end
end
