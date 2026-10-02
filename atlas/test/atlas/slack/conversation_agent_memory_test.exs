defmodule Atlas.Slack.ConversationAgentMemoryTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Memory
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Slack.Channel
  alias Atlas.Slack.ConversationAgent
  alias Condukt.Tool

  describe "internal_company_channel?/2" do
    test "true for an unshared, account-less :company channel" do
      channel = insert_channel!()
      assert ConversationAgent.internal_company_channel?(:company, channel)
    end

    test "false for externally shared channels" do
      channel = insert_channel!(%{is_ext_shared: true})
      refute ConversationAgent.internal_company_channel?(:company, channel)
    end

    test "false for account-linked channels" do
      account = insert_account!()
      channel = insert_channel!(%{account_id: account.id})
      refute ConversationAgent.internal_company_channel?(:company, channel)
    end

    test "false for the community app" do
      channel = insert_channel!(%{slack_app: :community})
      refute ConversationAgent.internal_company_channel?(:community, channel)
    end
  end

  describe "slack_session_options/3" do
    test "mounts memory tools on internal company channels" do
      channel = insert_channel!()

      opts = ConversationAgent.slack_session_options(:company, channel)
      tools = Keyword.fetch!(opts, :tools)
      names = Enum.map(tools, &Tool.name/1)

      assert "memory_save" in names
      assert "memory_recall" in names
      assert "search_atlas" in names

      search_atlas = Enum.find(tools, &(Tool.name(&1) == "search_atlas"))
      assert search_atlas.parameters.properties.domains.items.enum == ["atlas"]
    end

    test "does not mount memory tools on account-linked channels" do
      account = insert_account!()
      channel = insert_channel!(%{account_id: account.id})

      opts = ConversationAgent.slack_session_options(:company, channel)
      names = opts |> Keyword.fetch!(:tools) |> Enum.map(&Tool.name/1)

      refute "memory_save" in names
      refute "memory_recall" in names
      refute "search_atlas" in names
    end

    test "searches Atlas records through the Slack tool" do
      channel = insert_channel!()

      {:ok, record} =
        Search.upsert_record(
          %{
            source_type: "blog_post_idea",
            source_id: Ecto.UUID.generate(),
            title: "Remote cache economics",
            body: "Explain build cost reduction.",
            path: "/commercial/gtm/content/example"
          },
          embed?: false
        )

      tool =
        :company
        |> ConversationAgent.slack_session_options(channel)
        |> Keyword.fetch!(:tools)
        |> Enum.find(&(Tool.name(&1) == "search_atlas"))

      assert {:ok, %{results: [result], count: 1, domains: ["atlas"], available_domains: ["atlas"]}} =
               tool.call.(%{"query" => "build cost", "max_results" => 5}, %{assigns: %{}})

      assert result.id == record.id
      assert result.source_type == "blog_post_idea"
    end

    test "rejects document search through the Slack tool in ordinary internal channels" do
      channel = insert_channel!()

      tool =
        :company
        |> ConversationAgent.slack_session_options(channel)
        |> Keyword.fetch!(:tools)
        |> Enum.find(&(Tool.name(&1) == "search_atlas"))

      assert {:error, "Search domain documents is not available."} =
               tool.call.(%{"query" => "board consent", "domains" => ["documents"]}, %{assigns: %{}})
    end
  end

  describe "build_prompt/4" do
    test "prepends the global bulletin on internal company channels" do
      channel = insert_channel!()
      {:ok, _bulletin} = Memory.upsert_bulletin(:global, "Acme renews in Q3.")
      event = %{"ts" => "1.0", "thread_ts" => nil, "user" => "U1", "channel" => channel.channel_id}

      prompt = ConversationAgent.build_prompt(event, channel, nil, [])

      assert prompt =~ "Workspace memory bulletin:\nAcme renews in Q3."
    end

    test "does not prepend the bulletin on account-linked channels" do
      account = insert_account!()
      channel = insert_channel!(%{account_id: account.id})
      {:ok, _bulletin} = Memory.upsert_bulletin(:global, "Acme renews in Q3.")
      event = %{"ts" => "1.0", "thread_ts" => nil, "user" => "U1", "channel" => channel.channel_id}

      prompt = ConversationAgent.build_prompt(event, channel, nil, [])

      refute prompt =~ "Workspace memory bulletin"
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

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
