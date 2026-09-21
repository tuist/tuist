defmodule Atlas.Slack.ConversationAgentTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Documents.Document
  alias Atlas.GTM
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.Repo
  alias Atlas.Slack.Channel
  alias Atlas.Slack.ConversationAgent
  alias Atlas.Slack.User, as: SlackUser
  alias Atlas.Users.User
  alias Condukt.Tool

  test "creates an account through the Slack conversation tool" do
    tool = conversation_tool!("create_account")

    assert tool.parameters.required == ["name"]
    assert tool.parameters.properties.name.minLength == 1
    assert tool.parameters.properties.segment.enum == ["customer", "lead", "prospect"]
    assert tool.parameters.properties.segment.default == "prospect"

    assert {:ok, %{created: true, account: account}, %{found_account_id: account_id}} =
             tool.call.(%{"name" => "Acme Labs", "primary_domain" => "acme.example"}, %{assigns: %{}})

    assert account.name == "Acme Labs"
    assert account.account_key == "slack:acme-labs"
    assert account.segment == "prospect"
    assert account.primary_domain == "acme.example"
    assert account_id == account.id

    stored = Repo.get!(Account, account_id)
    assert stored.url == "https://acme.example"
    assert stored.metadata["created_from"] == "slack_conversation_agent"
  end

  test "returns an existing account instead of creating a duplicate through the Slack tool" do
    existing =
      %Account{}
      |> Account.changeset(%{
        account_key: "enterprise:acme-labs",
        name: "Acme Labs",
        segment: :customer
      })
      |> Repo.insert!()

    tool = conversation_tool!("create_account")

    assert {:ok, %{created: false, account: account}, %{found_account_id: account_id}} =
             tool.call.(%{"name" => "acme labs", "segment" => "prospect"}, %{assigns: %{}})

    assert account.id == existing.id
    assert account.segment == "customer"
    assert account_id == existing.id
    assert Repo.aggregate(Account, :count) == 1
  end

  test "captures a social-channel idea through the Slack conversation tool" do
    tool = conversation_tool!("capture_social_channel_idea")

    assert tool.parameters.required == ["title"]
    assert tool.parameters.properties.title.minLength == 1
    assert Map.keys(tool.parameters.properties) |> Enum.sort() == [:description, :title]

    slack_user = %SlackUser{
      slack_user_id: "U123",
      display_name: "Casey",
      email: "casey@example.com"
    }

    assert {:ok, %{captured: true, social_channel_idea: serialized}} =
             tool.call.(
               %{
                 "title" => "Turn the benchmark chart into a social post",
                 "description" => "Use the cache chart and ask platform teams what they would measure."
               },
               %{assigns: %{requester_slack_user: slack_user}}
             )

    idea = GTM.get_social_channel_idea(serialized.id)
    assert idea.created_by_agent == "slack"
    assert idea.title == "Turn the benchmark chart into a social post"
    assert idea.description == "Use the cache chart and ask platform teams what they would measure."
  end

  test "lists and fetches social-channel ideas through Slack conversation tools" do
    {:ok, idea} =
      GTM.create_social_channel_idea(%{
        "title" => "Share selective testing savings",
        "description" => "Turn saved waiting time into a short post."
      })

    list_tool = conversation_tool!("list_social_channel_ideas")
    get_tool = conversation_tool!("get_social_channel_idea")

    assert {:ok, %{social_channel_ideas: ideas, count: 1}} =
             list_tool.call.(%{"status" => "idea"}, %{assigns: %{}})

    assert [%{id: idea_id, title: "Share selective testing savings"}] = ideas
    assert idea_id == idea.id

    assert {:ok, %{social_channel_idea: serialized}} =
             get_tool.call.(%{"social_channel_idea_id" => idea.id}, %{assigns: %{}})

    assert serialized.id == idea.id
    assert serialized.post_revisions == []
  end

  test "creates and approves social post revisions through Slack conversation tools" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Iterate launch copy"})

    slack_user = %SlackUser{
      slack_user_id: "U123",
      display_name: "Casey",
      email: "casey@example.com"
    }

    create_tool = conversation_tool!("create_social_post_revision")
    update_tool = conversation_tool!("update_social_post_revision")

    assert {:ok, %{created: true, social_post_revision: serialized}} =
             create_tool.call.(
               %{
                 "social_channel_idea_id" => idea.id,
                 "body" => "Draft the launch post around saved waiting time.",
                 "notes" => "Captured from a Slack thread."
               },
               %{assigns: %{requester_slack_user: slack_user}}
             )

    revision = Repo.get!(SocialPostRevision, serialized.id)
    assert revision.social_channel_idea_id == idea.id
    assert revision.revision_number == 1
    assert revision.created_by_agent == "slack"
    assert revision.status == "draft"

    assert {:ok, %{updated: true, social_post_revision: approved}} =
             update_tool.call.(
               %{
                 "social_post_revision_id" => revision.id,
                 "body" => "Final launch post around saved waiting time.",
                 "status" => "approved"
               },
               %{assigns: %{requester_slack_user: slack_user}}
             )

    assert approved.status == "approved"
    assert approved.body == "Final launch post around saved waiting time."
    assert Repo.get!(SocialPostRevision, revision.id).status == "approved"
    assert GTM.get_social_channel_idea(idea.id).status == "approved"
  end

  test "create_social_post_revision returns a helpful error when the body is missing" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Needs a body"})

    create_tool = conversation_tool!("create_social_post_revision")

    assert {:error, message} =
             create_tool.call.(
               %{"social_channel_idea_id" => idea.id},
               %{assigns: %{}}
             )

    assert message =~ "body is required"
    assert Repo.all(SocialPostRevision) == []
  end

  test "does not expose retired customer outcome tools" do
    names = ConversationAgent.tools() |> Enum.map(&Tool.name/1)

    refute "list_account_outcomes" in names
    refute "list_account_outcome_proposals" in names
    refute "generate_account_outcome_proposals" in names
    refute "review_account_outcome" in names
  end

  test "lists account service levels through the Slack conversation tool" do
    account = insert_account!(%{account_key: "enterprise:zillow", name: "Zillow", segment: :customer})
    document = insert_document!(account, %{title: "Zillow Service Level Addendum"})
    check = insert_service_level_extraction_check!(account, document)

    service_level =
      insert_service_level!(account, document, check, %{
        name: "Monthly availability",
        category: "availability",
        target: "99.5% per month",
        measurement_window: "monthly",
        service_credit: "0.1% per 0.1% deviation, max 20%",
        source_page: 3,
        source_excerpt: "The Software as a Service is provided with an Availability of 99.5 % per month."
      })

    tool = conversation_tool!("list_account_service_levels")

    assert tool.description =~ "SLA commitments"

    assert {:ok, payload, %{found_account_id: account_id}} =
             tool.call.(%{}, %{assigns: %{found_account_id: account.id}})

    assert account_id == account.id
    assert payload.account.name == "Zillow"
    assert payload.service_level_count == 1

    assert [
             %{
               id: service_level_id,
               name: "Monthly availability",
               target: "99.5% per month",
               document_title: "Zillow Service Level Addendum",
               source_page: 3
             }
           ] = payload.service_levels

    assert service_level_id == service_level.id

    assert [
             %{
               status: "completed",
               document_title: "Zillow Service Level Addendum"
             }
           ] = payload.service_level_extraction_checks
  end

  test "registers the public URL content tool" do
    tool = conversation_tool!("fetch_url_content")
    spec = Tool.to_spec(tool)

    assert spec.parameters.required == ["url"]
    assert spec.parameters.properties.url.type == "string"
    assert spec.parameters.properties.url.minLength == 1
    assert spec.description =~ "Fetch and read the text content of a public URL."
  end

  test "registers the systems sub-agent for non-shared company bot channels" do
    mcp_user_email = "slack-agent-systems@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Slack Agent"})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_INTERNAL", channel_name: "eng"}

    options =
      :company
      |> ConversationAgent.slack_session_options(channel, mcp_user_email: mcp_user_email)

    refute Enum.any?(Keyword.fetch!(options, :tools), &(Tool.name(&1) == "list_accounts"))

    subagents = Keyword.fetch!(options, :subagents)
    systems_investigator = Keyword.fetch!(subagents, :systems_investigator)

    systems_tools = Keyword.fetch!(systems_investigator, :tools)
    assert Enum.any?(systems_tools, &(Tool.name(&1) == "list_accounts"))
  end

  test "does not expose finance or document tools directly on the Slack conversation agent" do
    mcp_user_email = "slack-agent-no-finance@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Slack Agent"})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_INTERNAL", channel_name: "eng"}

    options =
      ConversationAgent.slack_session_options(:company, channel, mcp_user_email: mcp_user_email)

    tool_names = options |> Keyword.fetch!(:tools) |> Enum.map(&Tool.name/1)

    refute "get_finance_overview" in tool_names
    refute "create_stripe_draft_invoice" in tool_names
    refute "list_documents" in tool_names
  end

  test "does not register the systems sub-agent in Slack Connect account channels" do
    channel = %Channel{
      slack_app: :company,
      channel_id: "C_CONNECT",
      channel_name: "customer",
      account_id: Atlas.UUIDv7.generate()
    }

    subagents =
      :company
      |> ConversationAgent.slack_session_options(channel)
      |> Keyword.fetch!(:subagents)

    refute Keyword.has_key?(subagents, :systems_investigator)
  end

  test "does not register the systems sub-agent for externally shared channels" do
    channel = %Channel{
      slack_app: :company,
      channel_id: "C_SHARED",
      channel_name: "shared",
      is_ext_shared: true
    }

    subagents =
      :company
      |> ConversationAgent.slack_session_options(channel)
      |> Keyword.fetch!(:subagents)

    refute Keyword.has_key?(subagents, :systems_investigator)
  end

  test "does not register the systems sub-agent for shared channels" do
    channel = %Channel{
      slack_app: :company,
      channel_id: "C_SHARED",
      channel_name: "shared",
      is_shared: true
    }

    subagents =
      :company
      |> ConversationAgent.slack_session_options(channel)
      |> Keyword.fetch!(:subagents)

    refute Keyword.has_key?(subagents, :systems_investigator)
  end

  test "does not register the systems sub-agent for the community app" do
    channel = %Channel{slack_app: :community, channel_id: "C_COMMUNITY", channel_name: "community"}

    subagents =
      :community
      |> ConversationAgent.slack_session_options(channel)
      |> Keyword.fetch!(:subagents)

    refute Keyword.has_key?(subagents, :systems_investigator)
  end

  test "build_prompt includes the full thread transcript and merges the latest reply" do
    channel = %Channel{slack_app: :company, channel_id: "C123", channel_name: "sales", account_id: "acc_123"}

    event = %{
      "channel" => "C123",
      "user" => "U123",
      "thread_ts" => "1710000000.100000",
      "ts" => "1710000002.100000",
      "text" => "<@U_ATLAS> the company is Toss and the domain is toss.im",
      "atlas_authorized_user_ids" => ["U_ATLAS"]
    }

    slack_user = %SlackUser{slack_user_id: "U123", display_name: "Pedro"}

    thread_messages = [
      %{
        user_id: "U123",
        text: "<@U_ATLAS> can you create an account for this one?",
        ts: "1710000000.100000",
        thread_ts: "1710000000.100000"
      },
      %{
        bot_id: "B_ATLAS",
        username: "Atlas",
        text: "I'd be happy to create an account.",
        ts: "1710000001.100000",
        thread_ts: "1710000000.100000"
      }
    ]

    prompt = ConversationAgent.build_prompt(event, channel, slack_user, thread_messages)

    assert prompt =~ "Thread transcript:"
    assert prompt =~ "- Pedro: can you create an account for this one?"
    assert prompt =~ "- Atlas: I'd be happy to create an account."
    assert prompt =~ "- Pedro: the company is Toss and the domain is toss.im"
  end

  test "build_prompt accepts thread messages decoded from Oban args" do
    event = %{
      "channel" => "C123",
      "user" => "U123",
      "thread_ts" => "1710000000.100000",
      "ts" => "1710000002.100000",
      "text" => "You were cool",
      "atlas_authorized_user_ids" => ["U_ATLAS"]
    }

    slack_user = %SlackUser{slack_user_id: "U123", display_name: "Pedro"}

    thread_messages = [
      %{
        "user_id" => "U123",
        "text" => "<@U_ATLAS> can you give us a summary of how we did financially in May?",
        "raw" => %{"ts" => "1710000000.100000"}
      },
      %{
        "bot_id" => "B_ATLAS",
        "username" => "Atlas",
        "text" => "I don't have access to internal financial data.",
        "ts" => "1710000001.100000"
      }
    ]

    prompt = ConversationAgent.build_prompt(event, nil, slack_user, thread_messages)

    assert prompt =~ "- Pedro: can you give us a summary of how we did financially in May?"
    assert prompt =~ "- Atlas: I don't have access to internal financial data."
    assert prompt =~ "- Pedro: You were cool"
  end

  test "build_prompt removes Slack mention tokens even when no authorized ids are present" do
    event = %{
      "channel" => "C123",
      "user" => "U123",
      "thread_ts" => "1710000000.100000",
      "ts" => "1710000002.100000",
      "text" => "<@uAtlas123> thanks for the context"
    }

    slack_user = %SlackUser{slack_user_id: "U123", display_name: "Pedro"}

    prompt = ConversationAgent.build_prompt(event, nil, slack_user, [])

    assert prompt =~ "- Pedro: thanks for the context"
    refute prompt =~ "<@uAtlas123>"
  end

  test "system prompt keeps Slack replies scoped and brief on stop requests" do
    prompt = ConversationAgent.system_prompt()

    assert prompt =~ "Answer only the question or request that was asked."
    assert prompt =~ "Do not volunteer follow-up actions"
    assert prompt =~ "If the user asks you to stop"
    assert prompt =~ "one short acknowledgment and nothing else"
    assert prompt =~ "Atlas sends no Slack message"
    assert prompt =~ "capture_social_channel_idea"
    assert prompt =~ "social-channel idea"
    assert prompt =~ "create_social_post_revision"
    assert prompt =~ "update_social_post_revision"
    assert prompt =~ "If a request is about company finance"
    assert prompt =~ "use the available Atlas MCP finance"
    assert prompt =~ "get_finance_overview"
    assert prompt =~ "list_finance_transactions"
    assert prompt =~ "get_finance_expense_reconciliation"
    assert prompt =~ "Treat its `complete` field as authoritative"
  end

  test "default Slack sessions include social idea and revision tools" do
    channel = %Channel{slack_app: :company, channel_id: "C_INTERNAL", channel_name: "eng"}

    tool_names =
      :company
      |> ConversationAgent.slack_session_options(channel)
      |> Keyword.fetch!(:tools)
      |> Enum.map(&Tool.name/1)

    assert "capture_social_channel_idea" in tool_names
    assert "list_social_channel_ideas" in tool_names
    assert "get_social_channel_idea" in tool_names
    assert "create_social_post_revision" in tool_names
    assert "update_social_post_revision" in tool_names
    assert tool_names == Enum.uniq(tool_names)
  end

  test "systems investigator prompt leaves finance summaries to the main agent" do
    systems_investigator =
      ConversationAgent.subagents([
        Condukt.tool(
          name: "list_accounts",
          description: "List accounts",
          parameters: %{"type" => "object"},
          call: fn _args, _ctx -> {:ok, %{}} end
        )
      ])
      |> Keyword.fetch!(:systems_investigator)

    prompt = Keyword.fetch!(systems_investigator, :system_prompt)

    assert prompt =~ "Finance requests should be answered by the main Slack agent"
    assert prompt =~ "production-system and infrastructure"
    refute prompt =~ "get_finance_month_summary"
  end

  test "executes Atlas MCP tools without a persistent MCP client pid" do
    mcp_user_email = "slack-agent-mcp-tool@example.com"
    insert_account!(%{account_key: "account:target", name: "Target", segment: :customer})

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Slack Agent"})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_INTERNAL", channel_name: "eng"}

    list_accounts =
      :company
      |> ConversationAgent.slack_session_options(channel, mcp_user_email: mcp_user_email)
      |> Keyword.fetch!(:subagents)
      |> Keyword.fetch!(:systems_investigator)
      |> Keyword.fetch!(:tools)
      |> Enum.find(&(Tool.name(&1) == "list_accounts"))

    assert {:ok, text} = Tool.execute(list_accounts, %{"query" => "Target"}, %{assigns: %{}})
    assert %{"accounts" => [%{"name" => "Target"}], "count" => 1} = JSON.decode!(text)
  end

  defp conversation_tool!(name) do
    Enum.find(ConversationAgent.tools(), &(Tool.name(&1) == name)) ||
      flunk("expected #{name} conversation tool")
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_document!(account, attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.pdf",
      content_type: "application/pdf",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.pdf",
      source: "upload",
      status: "ready"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Ecto.Changeset.change(account_id: account.id)
    |> Repo.insert!()
  end

  defp insert_service_level_extraction_check!(account, document) do
    %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}
    |> ServiceLevelExtractionCheck.changeset(%{
      agent_version: "service_level_extraction_agent:v1",
      document_checksum_sha256: document.checksum_sha256,
      status: "completed",
      started_at: ~U[2026-06-04 12:00:00Z],
      completed_at: ~U[2026-06-04 12:01:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_service_level!(account, document, check, attrs) do
    %ServiceLevel{
      account_id: account.id,
      document_id: document.id,
      service_level_extraction_check_id: check.id
    }
    |> ServiceLevel.changeset(attrs)
    |> Repo.insert!()
  end
end
