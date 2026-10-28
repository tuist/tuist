defmodule Atlas.Memory.Tools.MemoryRecallTest do
  use Atlas.DataCase, async: true

  alias Atlas.Memory
  alias Atlas.Memory.Tools
  alias Atlas.Repo
  alias Atlas.Slack.Channel
  alias Condukt.Tool

  describe "memory_recall_tool/2" do
    test "returns matching memories ordered by relevance" do
      channel = insert_channel!()
      {:ok, _} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, _} = Memory.create_node(%{kind: :preference, body: "Pat prefers Loom over Zoom."})

      tool = Tools.memory_recall_tool(channel, scope: :global)

      assert {:ok, %{memories: memories, memory_count: 1}} =
               Tool.execute(tool, %{"query" => "Acme"}, %{assigns: %{}})

      assert [%{body: "Acme renews in Q3 2026.", kind: "fact"}] = memories
    end

    test "filters by kind" do
      channel = insert_channel!()
      {:ok, _} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, _} = Memory.create_node(%{kind: :decision, body: "Acme deal needs legal review."})

      tool = Tools.memory_recall_tool(channel, scope: :global)

      assert {:ok, %{memory_count: 1, memories: [%{kind: "decision"}]}} =
               Tool.execute(tool, %{"query" => "Acme", "kind" => "decision"}, %{assigns: %{}})
    end

    test "searches the configured memory scope" do
      channel = insert_channel!()
      other_channel = insert_channel!()
      {:ok, _} = Memory.create_node(%{kind: :fact, body: "Global renewal context."})

      {:ok, _} =
        Memory.create_node(%{
          kind: :fact,
          body: "Channel renewal context.",
          scope: :channel,
          slack_channel_id: channel.id
        })

      {:ok, _} =
        Memory.create_node(%{
          kind: :fact,
          body: "Other channel renewal context.",
          scope: :channel,
          slack_channel_id: other_channel.id
        })

      tool = Tools.memory_recall_tool(channel, scope: :channel)

      assert {:ok, %{memory_count: 1, memories: [%{body: "Channel renewal context."}]}} =
               Tool.execute(tool, %{"query" => "renewal"}, %{assigns: %{}})
    end
  end

  defp insert_channel!(attrs \\ %{}) do
    defaults = %{
      slack_app: :company,
      channel_id: "C#{System.unique_integer([:positive])}",
      channel_name: "general",
      is_shared: false,
      is_ext_shared: false
    }

    Repo.insert!(struct(Channel, Map.merge(defaults, attrs)))
  end
end
