defmodule Condukt.Compactor.ToolResultPrune do
  @moduledoc """
  Replaces the content of old tool result messages with a small placeholder,
  preserving the message structure (and the assistant's tool call reasoning)
  so the model still sees that the tool was invoked.

  This is the cheapest compaction strategy: no turns are dropped, only
  oversized historical payloads (large file reads, command output, etc.) are
  elided. Often enough on its own for coding agents.

  ## Options

  - `:keep_recent` - number of trailing tool results to leave intact
    (default: `5`).
  - `:max_size` - tool result payloads larger than this many bytes are elided
    when they fall outside the recent window (default: `4096`).

  ## Example

      MyApp.Agent.start_link(
        compactor: {Condukt.Compactor.ToolResultPrune, keep_recent: 10, max_size: 2_000}
      )
  """

  @behaviour Condukt.Compactor

  alias Condukt.Message

  @default_keep_recent 5
  @default_max_size 4096

  @impl true
  def compact(messages, opts) do
    keep_recent = Keyword.get(opts, :keep_recent, @default_keep_recent)
    max_size = Keyword.get(opts, :max_size, @default_max_size)

    total = Enum.count(messages, &(&1.role == :tool_result))
    threshold = max(0, total - keep_recent)

    {result, _} =
      Enum.map_reduce(messages, 0, fn
        %Message{role: :tool_result} = msg, idx ->
          msg = if idx < threshold, do: elide(msg, max_size), else: msg
          {msg, idx + 1}

        msg, idx ->
          {msg, idx}
      end)

    {:ok, result}
  end

  defp elide(%Message{content: content} = msg, max_size) when is_binary(content) do
    if byte_size(content) > max_size do
      %{msg | content: "<elided: #{byte_size(content)} bytes>"}
    else
      msg
    end
  end

  defp elide(%Message{content: content} = msg, max_size) do
    encoded = JSON.encode!(content)

    if byte_size(encoded) > max_size do
      %{msg | content: "<elided: #{byte_size(encoded)} bytes>"}
    else
      msg
    end
  end
end
