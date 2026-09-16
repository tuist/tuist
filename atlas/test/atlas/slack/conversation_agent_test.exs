defmodule Atlas.Slack.ConversationAgentTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Agents.Identity
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.GTM
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.Repo
  alias Atlas.Slack.AgentIdentities
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
      |> ConversationAgent.slack_session_options(channel, Identity.default(), mcp_user_email: mcp_user_email)

    refute Enum.any?(Keyword.fetch!(options, :tools), &(Tool.name(&1) == "list_accounts"))

    subagents = Keyword.fetch!(options, :subagents)
    systems_investigator = Keyword.fetch!(subagents, :systems_investigator)

    systems_tools = Keyword.fetch!(systems_investigator, :tools)
    assert Enum.any?(systems_tools, &(Tool.name(&1) == "list_accounts"))
  end

  test "adds configured channel persona and direct tool access by Slack app and channel id" do
    mcp_user_email = "slack-agent-identity@example.com"

    identity = %Identity{
      persona: :leadership,
      tool_groups: ["finance", "documents"],
      tool_groups_by_agent: %{"conversation" => ["finance", "documents"], "systems_investigator" => []}
    }

    model = ReqLLM.model!(%{provider: :openai, id: "Balanced"})

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Identity Agent", role: :executive})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_POLICY", channel_name: "fixture-channel"}

    options =
      :company
      |> ConversationAgent.slack_session_options(channel, identity,
        mcp_user_email: mcp_user_email,
        model: model,
        api_key: "llm-api-key",
        base_url: "https://hive.tuist.dev/inference/v1",
        timeout: 330_000
      )

    conversation_tools = Keyword.fetch!(options, :tools)
    assert Enum.any?(conversation_tools, &(Tool.name(&1) == "get_finance_overview"))
    assert Enum.any?(conversation_tools, &(Tool.name(&1) == "list_documents"))
    assert Enum.any?(conversation_tools, &(Tool.name(&1) == "create_stripe_draft_invoice"))

    subagents = Keyword.fetch!(options, :subagents)
    account_investigator = Keyword.fetch!(subagents, :account_investigator)
    assert Keyword.fetch!(account_investigator, :model) == model
    assert Keyword.fetch!(account_investigator, :api_key) == "llm-api-key"
    assert Keyword.fetch!(account_investigator, :base_url) == "https://hive.tuist.dev/inference/v1"
    assert Keyword.fetch!(account_investigator, :timeout) == 330_000

    systems_investigator = Keyword.fetch!(subagents, :systems_investigator)
    assert Keyword.fetch!(systems_investigator, :model) == model
    assert Keyword.fetch!(systems_investigator, :api_key) == "llm-api-key"
    assert Keyword.fetch!(systems_investigator, :base_url) == "https://hive.tuist.dev/inference/v1"
    assert Keyword.fetch!(systems_investigator, :timeout) == 330_000

    systems_tools = Keyword.fetch!(systems_investigator, :tools)
    assert Enum.any?(systems_tools, &(Tool.name(&1) == "list_accounts"))
    refute Enum.any?(systems_tools, &(Tool.name(&1) == "get_finance_overview"))

    prompt =
      ConversationAgent.build_prompt(
        %{"channel" => "C_POLICY", "user" => "U123", "ts" => "1710000000.100000", "text" => "How are we doing?"},
        channel,
        nil,
        [],
        identity
      )

    assert prompt =~ "Act as a leadership operator"
    assert prompt =~ "finance data"
    assert prompt =~ "finance tools are available directly to the Slack agent"
    assert prompt =~ "document tools are available directly to the Slack agent"
    refute prompt =~ "#fixture-channel"
    refute prompt =~ "Channel: fixture-channel"
  end

  test "searches documents from Slack when the channel has document access" do
    mcp_user_email = "slack-agent-document-search@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Document Search Agent", role: :executive})
    |> Repo.insert!()

    account = insert_account!(%{account_key: "account:leadership-doc", name: "Leadership Doc", segment: :customer})
    document = insert_document!(account, %{title: "Leadership Board Consent"})

    page =
      %DocumentPage{}
      |> DocumentPage.changeset(%{
        document_id: document.id,
        page_number: 1,
        content: "Signed board consent appointing a managing director."
      })
      |> Repo.insert!()

    identity = %Identity{
      persona: :leadership,
      tool_groups: ["documents"],
      tool_groups_by_agent: %{"conversation" => ["documents"], "systems_investigator" => []}
    }

    channel = %Channel{slack_app: :company, channel_id: "C_LEADERSHIP", channel_name: "leadership"}

    search_atlas =
      :company
      |> ConversationAgent.slack_session_options(channel, identity, mcp_user_email: mcp_user_email)
      |> Keyword.fetch!(:tools)
      |> Enum.find(&(Tool.name(&1) == "search_atlas"))

    assert {:ok, text} =
             Tool.execute(
               search_atlas,
               %{"query" => "board consent", "domains" => ["documents"], "page_size" => 5},
               %{assigns: %{}}
             )

    assert %{
             "results" => [
               %{
                 "source_type" => "document_page",
                 "source_id" => source_id,
                 "document_id" => document_id,
                 "page_number" => 1
               }
             ],
             "domains" => ["documents"]
           } = JSON.decode!(text)

    assert source_id == page.id
    assert document_id == document.id
  end

  test "adds finance tools for channels granted finance by configured identity" do
    mcp_user_email = "slack-agent-configured-identity@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Configured Identity Agent", role: :executive})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_CONFIGURED", channel_name: "private-channel"}

    identity =
      AgentIdentities.for_channel(:company, channel, [
        %{
          slack_app: :company,
          channel_id: "C_CONFIGURED",
          persona: :leadership,
          tool_groups_by_agent: %{
            conversation: ["finance", "documents"],
            systems_investigator: []
          }
        }
      ])

    options =
      ConversationAgent.slack_session_options(:company, channel, identity, mcp_user_email: mcp_user_email)

    conversation_tools = Keyword.fetch!(options, :tools)
    assert Enum.any?(conversation_tools, &(Tool.name(&1) == "create_stripe_draft_invoice"))

    prompt =
      ConversationAgent.build_prompt(
        %{"channel" => "C_CONFIGURED", "user" => "U123", "ts" => "1710000000.100000", "text" => "invoice acme"},
        channel,
        nil,
        [],
        identity
      )

    assert prompt =~ "Act as a leadership operator"
    assert prompt =~ "finance tools are available directly to the Slack agent"
  end

  test "applies persisted identity requester rules and prompt context" do
    mcp_user_email = "slack-agent-leadership@example.com"
    employee_email = "leadership-employee@example.com"
    executive_email = "leadership-executive@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Leadership Agent", role: :executive})
    |> Repo.insert!()

    %User{}
    |> User.changeset(%{email: employee_email, name: "Employee Requester", role: :employee})
    |> Repo.insert!()

    %User{}
    |> User.changeset(%{email: executive_email, name: "Executive Requester", role: :executive})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_LEADERSHIP", channel_name: "leadership"}

    %Identity{}
    |> Identity.changeset(%{
      key: "leadership",
      display_name: "Atlas Leadership",
      bindings: %{slack: %{app: :company, channel_ids: ["C_LEADERSHIP"]}},
      persona: :leadership,
      tool_groups_by_agent: %{
        conversation: ["finance", "documents"],
        systems_investigator: []
      },
      service_user_email: mcp_user_email,
      memory_scope: :disabled,
      requester_rules: %{"finance" => "executive"}
    })
    |> Repo.insert!()

    identity = ConversationAgent.agent_identity(:company, channel)
    employee = %SlackUser{slack_app: :company, slack_user_id: "U_EMPLOYEE", email: employee_email}

    employee_options =
      ConversationAgent.slack_session_options(:company, channel, identity, requester_slack_user: employee)

    employee_tool_names =
      employee_options
      |> Keyword.fetch!(:tools)
      |> Enum.map(&Tool.name/1)

    assert "list_documents" in employee_tool_names
    refute "create_stripe_draft_invoice" in employee_tool_names
    refute "memory_save" in employee_tool_names

    assert Keyword.fetch!(employee_options, :assigns).agent_identity_key == "leadership"

    executive = %SlackUser{slack_app: :company, slack_user_id: "U_EXECUTIVE", email: executive_email}

    executive_tool_names =
      :company
      |> ConversationAgent.slack_session_options(channel, identity, requester_slack_user: executive)
      |> Keyword.fetch!(:tools)
      |> Enum.map(&Tool.name/1)

    assert "create_stripe_draft_invoice" in executive_tool_names

    prompt =
      ConversationAgent.build_prompt(
        %{"channel" => "C_LEADERSHIP", "user" => "U123", "ts" => "1710000000.100000", "text" => "invoice acme"},
        channel,
        nil,
        [],
        identity
      )

    assert prompt =~ "Atlas identity: Atlas Leadership (leadership)."
    assert prompt =~ "Act as a leadership operator"
  end

  test "adds finance tools for executive requesters in other internal channels" do
    mcp_user_email = "slack-agent-executive-requester@example.com"
    executive_email = "executive-requester@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Slack Agent"})
    |> Repo.insert!()

    %User{}
    |> User.changeset(%{email: executive_email, name: "Executive Requester", role: :executive})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_SALES", channel_name: "sales"}
    requester = %SlackUser{slack_app: :company, slack_user_id: "U_EXEC", email: executive_email}

    options =
      ConversationAgent.slack_session_options(:company, channel, Identity.default(),
        mcp_user_email: mcp_user_email,
        requester_slack_user: requester
      )

    assert Enum.any?(Keyword.fetch!(options, :tools), &(Tool.name(&1) == "create_stripe_draft_invoice"))
  end

  test "hides finance tools from non-executive requesters in ordinary channels" do
    mcp_user_email = "slack-agent-employee-requester@example.com"
    employee_email = "employee-requester@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Slack Agent", role: :executive})
    |> Repo.insert!()

    %User{}
    |> User.changeset(%{email: employee_email, name: "Employee Requester", role: :employee})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_SALES", channel_name: "sales"}
    requester = %SlackUser{slack_app: :company, slack_user_id: "U_EMPLOYEE", email: employee_email}

    options =
      ConversationAgent.slack_session_options(:company, channel, Identity.default(),
        mcp_user_email: mcp_user_email,
        requester_slack_user: requester
      )

    refute Enum.any?(Keyword.fetch!(options, :tools), &(Tool.name(&1) == "create_stripe_draft_invoice"))
  end

  test "keeps explicitly mapped MCP tool groups available to configured subagents" do
    mcp_user_email = "slack-agent-mapped@example.com"
    executive_email = "mapped-executive@example.com"

    identity = %Identity{
      tool_groups: ["finance", "observability"],
      tool_groups_by_agent: %{"conversation" => [], "systems_investigator" => ["finance", "observability"]}
    }

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Mapped Agent"})
    |> Repo.insert!()

    %User{}
    |> User.changeset(%{email: executive_email, name: "Mapped Executive", role: :executive})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_MAPPED", channel_name: "mapped-channel"}
    requester = %SlackUser{slack_app: :company, slack_user_id: "U_MAPPED_EXEC", email: executive_email}

    options =
      ConversationAgent.slack_session_options(:company, channel, identity,
        mcp_user_email: mcp_user_email,
        requester_slack_user: requester
      )

    assert Enum.any?(Keyword.fetch!(options, :tools), &(Tool.name(&1) == "get_finance_overview"))

    systems_investigator =
      options
      |> Keyword.fetch!(:subagents)
      |> Keyword.fetch!(:systems_investigator)

    systems_tools = Keyword.fetch!(systems_investigator, :tools)
    assert Enum.any?(systems_tools, &(Tool.name(&1) == "get_finance_overview"))
  end

  test "uses configured leadership identity for the company leadership channel" do
    mcp_user_email = "slack-agent-leadership-configured@example.com"
    executive_email = "leadership-configured-executive@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Leadership Agent"})
    |> Repo.insert!()

    executive =
      %User{}
      |> User.changeset(%{email: executive_email, name: "Leadership Executive", role: :executive})
      |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_LEADERSHIP", channel_name: "leadership"}

    identity =
      AgentIdentities.for_channel(:company, channel, [
        %{
          workspace: "company",
          channel_id: "C_LEADERSHIP",
          key: "leadership",
          display_name: "Leadership",
          persona: "leadership",
          memory_scope: "channel",
          requester_rules: %{"finance" => "executive"},
          tool_groups_by_agent: %{
            conversation: ["finance", "documents"],
            systems_investigator: []
          }
        }
      ])

    assert identity.key == "leadership"
    assert identity.persona == :leadership
    assert identity.memory_scope == :channel

    options =
      ConversationAgent.slack_session_options(:company, channel, identity,
        mcp_user_email: mcp_user_email,
        requester_atlas_user: executive
      )

    conversation_tools = Keyword.fetch!(options, :tools)
    assert Enum.any?(conversation_tools, &(Tool.name(&1) == "list_documents"))
    assert Enum.any?(conversation_tools, &(Tool.name(&1) == "create_stripe_draft_invoice"))

    prompt =
      ConversationAgent.build_prompt(
        %{"channel" => "C_LEADERSHIP", "user" => "U123", "ts" => "1710000000.100000", "text" => "runway?"},
        channel,
        nil,
        [],
        identity
      )

    assert prompt =~ "Act as a leadership operator"
  end

  test "does not infer an identity for company engineering channels" do
    mcp_user_email = "slack-agent-engineering-default@example.com"

    %User{}
    |> User.changeset(%{email: mcp_user_email, name: "Engineering Agent"})
    |> Repo.insert!()

    channel = %Channel{slack_app: :company, channel_id: "C_ENGINEERING", channel_name: "engineering"}
    identity = ConversationAgent.agent_identity(:company, channel)

    assert identity.key == "default"

    options =
      ConversationAgent.slack_session_options(:company, channel, identity, mcp_user_email: mcp_user_email)

    refute Enum.any?(Keyword.fetch!(options, :tools), &(Tool.name(&1) == "list_accounts"))

    systems_investigator =
      options
      |> Keyword.fetch!(:subagents)
      |> Keyword.fetch!(:systems_investigator)

    systems_tools = Keyword.fetch!(systems_investigator, :tools)
    assert Enum.any?(systems_tools, &(Tool.name(&1) == "list_accounts"))

    refute Identity.persona_instructions(identity)
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
      |> ConversationAgent.slack_session_options(channel, Identity.default(), mcp_user_email: mcp_user_email)
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
