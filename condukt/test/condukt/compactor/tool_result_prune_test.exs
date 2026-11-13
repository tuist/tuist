defmodule Condukt.Compactor.ToolResultPruneTest do
  use ExUnit.Case, async: true

  alias Condukt.Compactor.ToolResultPrune
  alias Condukt.Message

  defp tool_call_msg(id, name \\ "read", args \\ %{}) do
    Message.assistant([{:tool_call, id, name, args}])
  end

  test "elides oversized old tool results and keeps recent ones intact" do
    big = String.duplicate("x", 5_000)

    messages = [
      Message.user("u"),
      tool_call_msg("a"),
      Message.tool_result("a", big),
      tool_call_msg("b"),
      Message.tool_result("b", big),
      tool_call_msg("c"),
      Message.tool_result("c", big)
    ]

    {:ok, pruned} = ToolResultPrune.compact(messages, keep_recent: 1, max_size: 1_000)

    [_, _, a_result, _, b_result, _, c_result] = pruned

    assert a_result.content =~ "<elided"
    assert b_result.content =~ "<elided"
    assert c_result.content == big
  end

  test "leaves small tool results alone even when out of the recent window" do
    messages = [
      tool_call_msg("a"),
      Message.tool_result("a", "tiny"),
      tool_call_msg("b"),
      Message.tool_result("b", "tiny"),
      tool_call_msg("c"),
      Message.tool_result("c", "tiny")
    ]

    {:ok, pruned} = ToolResultPrune.compact(messages, keep_recent: 1, max_size: 1_000)

    assert Enum.all?(pruned, fn
             %Message{role: :tool_result, content: c} -> c == "tiny"
             _ -> true
           end)
  end

  test "encodes non-binary tool result content before measuring size" do
    payload = %{"data" => String.duplicate("y", 5_000)}

    messages = [
      tool_call_msg("a"),
      Message.tool_result("a", payload),
      tool_call_msg("b"),
      Message.tool_result("b", "recent")
    ]

    {:ok, [_, a_result, _, b_result]} =
      ToolResultPrune.compact(messages, keep_recent: 1, max_size: 1_000)

    assert a_result.content =~ "<elided"
    assert b_result.content == "recent"
  end
end
