defmodule Condukt.Compactor.SlidingTest do
  use ExUnit.Case, async: true

  alias Condukt.Compactor.Sliding
  alias Condukt.Message

  defp tool_call_msg(id, name \\ "read", args \\ %{}) do
    Message.assistant([{:tool_call, id, name, args}])
  end

  test "returns messages unchanged when below the keep threshold" do
    messages = for i <- 1..5, do: Message.user("hi #{i}")
    assert {:ok, ^messages} = Sliding.compact(messages, keep: 10)
  end

  test "keeps the last N messages when over the threshold" do
    messages = for i <- 1..30, do: Message.user("hi #{i}")
    {:ok, kept} = Sliding.compact(messages, keep: 5)

    assert length(kept) == 5
    assert Enum.map(kept, & &1.content) == ["hi 26", "hi 27", "hi 28", "hi 29", "hi 30"]
  end

  test "drops orphaned tool results whose tool call was discarded" do
    old = tool_call_msg("call-old")
    old_result = Message.tool_result("call-old", "old result")
    recent = tool_call_msg("call-recent")
    recent_result = Message.tool_result("call-recent", "recent result")

    messages = [Message.user("u1"), old, old_result, Message.user("u2"), recent, recent_result]
    {:ok, kept} = Sliding.compact(messages, keep: 4)

    ids = Enum.map(kept, & &1.tool_call_id)
    assert "call-recent" in ids
    refute "call-old" in ids
    assert length(kept) == 3
  end

  test "uses default keep when no option is provided" do
    messages = for i <- 1..50, do: Message.user("hi #{i}")
    {:ok, kept} = Sliding.compact(messages, [])
    assert length(kept) == 20
  end
end
