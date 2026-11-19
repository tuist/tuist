defmodule Condukt.Compactor.Sliding do
  @moduledoc """
  Keeps the last N messages of the conversation.

  Tool results whose originating tool call has been dropped are also removed,
  since most providers reject orphaned tool results.

  ## Options

  - `:keep` - number of trailing messages to retain (default: `20`).

  When a native session compacts because the provider rejected a request as
  too long, it passes `context_overflow: true`. Sliding then keeps half as
  many messages as it otherwise would (half of `:keep`, or half of a shorter
  history), and at least one. That window starts before a batch of tool
  results rather than inside it, so recent tool calls keep their results.

  ## Example

      MyApp.Agent.start_link(
        compactor: {Condukt.Compactor.Sliding, keep: 40}
      )
  """

  @behaviour Condukt.Compactor

  alias Condukt.Message

  @default_keep 20

  @impl true
  def compact(messages, opts) do
    keep = Keyword.get(opts, :keep, @default_keep)
    keep = if opts[:context_overflow], do: overflow_keep(messages, keep), else: keep

    if length(messages) <= keep do
      {:ok, messages}
    else
      messages
      |> Enum.take(-keep)
      |> drop_orphaned_tool_results()
      |> then(&{:ok, &1})
    end
  end

  defp overflow_keep(messages, keep) do
    count = length(messages)
    cut = count - max(div(min(keep, count), 2), 1)

    batch =
      messages |> Enum.take(cut + 1) |> Enum.reverse() |> Enum.take_while(&(&1.role == :tool_result)) |> length()

    count - max(cut - batch, 0)
  end

  defp drop_orphaned_tool_results(messages) do
    valid_ids = tool_call_ids(messages)

    Enum.reject(messages, fn
      %Message{role: :tool_result, tool_call_id: id} ->
        not MapSet.member?(valid_ids, id)

      _ ->
        false
    end)
  end

  defp tool_call_ids(messages) do
    messages
    |> Enum.flat_map(fn
      %Message{role: :assistant, content: blocks} when is_list(blocks) ->
        for {:tool_call, id, _name, _args} <- blocks, do: id

      _ ->
        []
    end)
    |> MapSet.new()
  end
end
