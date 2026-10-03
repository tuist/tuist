defmodule Atlas.Memory.Tools.MemorySaveTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Memory
  alias Atlas.Memory.Tools
  alias Atlas.Repo
  alias Atlas.Slack.API, as: SlackAPI
  alias Atlas.Slack.Channel
  alias Condukt.Tool

  describe "memory_save_tool/4" do
    test "proposes a pending memory, posts a Slack confirmation, and stamps the proposal ts" do
      channel = insert_channel!()
      thread_ts = "1700000000.000100"

      expect(SlackAPI, :post_message, fn :company, channel_id, text, blocks, opts ->
        assert channel_id == channel.channel_id
        assert is_binary(text)
        assert text =~ "Acme renews in Q3 2026."
        assert text =~ "React :white_check_mark:"
        assert is_list(blocks) and blocks != []
        assert Keyword.get(opts, :thread_ts) == thread_ts
        {:ok, %{"ts" => "1700000000.000200"}}
      end)

      tool = Tools.memory_save_tool(channel, nil, thread_ts, scope: :global)

      assert {:ok, result} =
               Tool.execute(
                 tool,
                 %{"kind" => "fact", "body" => "Acme renews in Q3 2026."},
                 %{assigns: %{}}
               )

      assert %{saved: :pending, memory: %{id: id, kind: "fact", confirmation: "pending"}} = result

      assert [stored] = Memory.list_nodes(scope: :global, include_pending: true)
      assert stored.id == id
      assert stored.confirmation == :pending
      assert stored.proposal_slack_ts == "1700000000.000200"
      assert stored.slack_channel_id == channel.id
    end

    test "errors when no thread_ts is in scope" do
      channel = insert_channel!()
      tool = Tools.memory_save_tool(channel, nil, nil, scope: :global)

      assert {:error, message} =
               Tool.execute(
                 tool,
                 %{"kind" => "fact", "body" => "..."},
                 %{assigns: %{}}
               )

      assert message =~ "active Slack thread"
      assert Memory.list_nodes(scope: :global, include_pending: true) == []
    end

    test "can propose channel-scoped memories" do
      channel = insert_channel!()
      thread_ts = "1700000000.000100"

      expect(SlackAPI, :post_message, fn _, _, _, _, _ ->
        {:ok, %{"ts" => "1700000000.000200"}}
      end)

      tool = Tools.memory_save_tool(channel, nil, thread_ts, scope: :channel)

      assert {:ok, %{memory: %{id: id}}} =
               Tool.execute(
                 tool,
                 %{"kind" => "fact", "body" => "The channel prefers short renewal updates."},
                 %{assigns: %{}}
               )

      assert [] = Memory.list_nodes(scope: :global, include_pending: true)
      assert [stored] = Memory.list_nodes(scope: :channel, include_pending: true)
      assert stored.id == id
      assert stored.slack_channel_id == channel.id
    end

    test "returns an error for an unknown kind" do
      channel = insert_channel!()
      tool = Tools.memory_save_tool(channel, nil, "1700000000.000100", scope: :global)

      assert {:error, message} =
               Tool.execute(tool, %{"kind" => "rumor", "body" => "..."}, %{assigns: %{}})

      assert message =~ "kind must be one of"
    end

    test "pending proposals are excluded from default recall and from confirmed listings" do
      channel = insert_channel!()
      thread_ts = "1700000000.000100"

      expect(SlackAPI, :post_message, fn _, _, _, _, _ ->
        {:ok, %{"ts" => "1700000000.000200"}}
      end)

      tool = Tools.memory_save_tool(channel, nil, thread_ts, scope: :global)

      assert {:ok, _} =
               Tool.execute(
                 tool,
                 %{"kind" => "fact", "body" => "Acme renews in Q3 2026."},
                 %{assigns: %{}}
               )

      assert Memory.list_nodes(scope: :global) == []
      assert Memory.search_nodes("Acme") == []
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
