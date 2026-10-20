defmodule Atlas.Slack.MessageTest do
  use ExUnit.Case, async: true

  alias Atlas.Slack.Message

  describe "top_level?/1" do
    test "is true when thread_ts is nil" do
      assert Message.top_level?(%Message{slack_ts: "1.0", thread_ts: nil})
    end

    test "is true when thread_ts equals slack_ts (Slack's parent representation)" do
      assert Message.top_level?(%Message{slack_ts: "1.0", thread_ts: "1.0"})
    end

    test "is false when thread_ts differs from slack_ts (a reply)" do
      refute Message.top_level?(%Message{slack_ts: "2.0", thread_ts: "1.0"})
    end
  end
end
