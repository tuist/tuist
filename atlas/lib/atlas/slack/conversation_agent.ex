defmodule Atlas.Slack.ConversationAgent do
  @moduledoc """
  Slack-facing routing agent for Slack thread conversations.

  The agent keeps the conversation itself lightweight while exposing
  account-scoped tools and a sub-agent route for deeper investigation work.
  Slack rendering and streaming live in `Atlas.Slack.ConversationResponder`.
  """

  use Condukt

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.Outcome
  alias Atlas.Agents.StyleGuide
  alias Atlas.Audit
  alias Atlas.ChangesetErrors
  alias Atlas.GTM
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.Memory
  alias Atlas.Memory.Bulletin
  alias Atlas.Memory.Tools, as: MemoryTools
  alias Atlas.Repo
  alias Atlas.Search.Federated, as: FederatedSearch
  alias Atlas.Slack.AgentConfig
  alias Atlas.Slack.Channel
  alias Atlas.Slack.MCPTools
  alias Atlas.Slack.URLContent
  alias Atlas.Slack.User
  alias Atlas.Users

  require Logger

  @recent_event_limit 20
  @tool_result_limit 12
  @service_level_result_limit 50
  @default_mcp_user_email "pedro@tuist.dev"

  # Tool groups reachable through the systems_investigator subagent. Finance
  # and documents are intentionally omitted for now: they were previously
  # routed to the direct conversation agent via per-channel identities, and
  # will be reintroduced when the Slack bridge story is redesigned.
  @systems_investigator_tool_groups ["contracts", "admin", "hardware", "observability"]

  @impl true
  def tools do
    [
      URLContent,
      find_account_tool(),
      create_account_tool(),
      get_account_context_tool(),
      list_account_service_levels_tool(),
      list_account_events_tool(),
      capture_blog_post_idea_tool(),
      capture_social_channel_idea_tool(),
      list_social_channel_ideas_tool(),
      get_social_channel_idea_tool(),
      create_social_post_revision_tool(),
      update_social_post_revision_tool()
    ]
    |> Kernel.++(legacy_outcome_tools())
  end

  # Keep retired tool definitions readable while ensuring they are not exposed
  # to the Slack agent or callable by it.
  defp legacy_outcome_tools do
    [
      list_account_outcomes_tool(),
      list_account_outcome_proposals_tool(),
      generate_account_outcome_proposals_tool(),
      update_account_outcome_proposal_tool(),
      approve_account_outcome_proposal_tool(),
      reject_account_outcome_proposal_tool(),
      review_account_outcome_tool()
    ]
    |> Enum.take(0)
  end

  @impl true
  def subagents do
    subagents([])
  end

  def subagents(systems_tools, opts \\ []) when is_list(systems_tools) do
    child_session_opts = Keyword.take(opts, [:model, :api_key, :base_url, :timeout])

    base_subagents = [
      account_investigator:
        [
          system_prompt: account_investigator_prompt(),
          tools: tools(),
          load_project_instructions: false,
          max_turns: 6
        ] ++ child_session_opts
    ]

    case systems_tools do
      [] ->
        base_subagents

      [_tool | _] ->
        Keyword.put(
          base_subagents,
          :systems_investigator,
          [
            system_prompt: systems_investigator_prompt(),
            tools: systems_tools,
            load_project_instructions: false,
            max_turns: 8
          ] ++ child_session_opts
        )
    end
  end

  def slack_session_options(app_key, channel, opts \\ []) do
    conversation_tools = mcp_tools_for_agent(app_key, channel, :conversation, opts)
    systems_tools = mcp_tools_for_agent(app_key, channel, :systems_investigator, opts)
    memory_tools = memory_tools_for(app_key, channel, opts)
    atlas_search_tools = atlas_search_tools_for(app_key, channel, conversation_tools)

    [
      assigns: slack_session_assigns(opts),
      tools: unique_tools_by_name(tools() ++ atlas_search_tools ++ conversation_tools ++ memory_tools),
      subagents: subagents(systems_tools, opts)
    ]
  end

  @doc """
  True when the channel is an internal company workspace channel that
  everyone on the team has access to. Memory tools and the bulletin only
  activate in these channels: Slack Connect, externally shared, and
  account-linked channels are excluded.
  """
  def internal_company_channel?(:company, %Channel{is_shared: false, is_ext_shared: false, account_id: nil}), do: true

  def internal_company_channel?(_app_key, _channel), do: false

  defp slack_session_assigns(opts) do
    %{requester_slack_user: Keyword.get(opts, :requester_slack_user)}
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp memory_tools_for(app_key, channel, opts) do
    if internal_company_channel?(app_key, channel) do
      MemoryTools.tools(
        channel,
        Keyword.get(opts, :requester_slack_user),
        Keyword.get(opts, :thread_ts),
        scope: :global
      )
    else
      []
    end
  end

  defp atlas_search_tools_for(app_key, channel, conversation_tools) do
    if internal_company_channel?(app_key, channel) and not tool_mounted?(conversation_tools, "search_atlas") do
      [atlas_search_tool(slack_search_domains(conversation_tools))]
    else
      []
    end
  end

  defp slack_search_domains(conversation_tools) do
    domains = [FederatedSearch.atlas_domain()]

    if tool_mounted?(conversation_tools, "search_documents") do
      domains ++ [FederatedSearch.documents_domain()]
    else
      domains
    end
  end

  defp tool_mounted?(tools, name) do
    Enum.any?(tools, &(Condukt.Tool.name(&1) == name))
  end

  defp unique_tools_by_name(tools) do
    Enum.uniq_by(tools, &Condukt.Tool.name/1)
  end

  defp mcp_tools_for_agent(app_key, channel, agent, opts) do
    tool_groups = tool_groups_for_agent(agent)

    should_mount? =
      agent == :systems_investigator or tool_groups != []

    if mcp_tools_allowed?(app_key, channel, opts) and should_mount? do
      build_mcp_tools(app_key, channel, agent, tool_groups, opts)
    else
      []
    end
  end

  defp tool_groups_for_agent(:systems_investigator), do: @systems_investigator_tool_groups
  defp tool_groups_for_agent(_agent), do: []

  def mcp_tools_allowed?(app_key, channel), do: mcp_tools_allowed?(app_key, channel, [])

  def mcp_tools_allowed?(:company, %Channel{} = channel, opts) do
    cond do
      externally_shared_channel?(channel) -> false
      account_linked_channel?(channel) -> requester_executive?(opts)
      true -> true
    end
  end

  def mcp_tools_allowed?(_app_key, _channel, _opts), do: false

  def slack_connect_channel?(%Channel{} = channel),
    do: externally_shared_channel?(channel) or account_linked_channel?(channel)

  def slack_connect_channel?(_channel), do: false

  defp externally_shared_channel?(%Channel{is_ext_shared: true}), do: true
  defp externally_shared_channel?(%Channel{is_shared: true}), do: true
  defp externally_shared_channel?(_channel), do: false

  defp account_linked_channel?(%Channel{account_id: account_id}) when not is_nil(account_id), do: true
  defp account_linked_channel?(_channel), do: false

  defp requester_executive?(opts) do
    opts
    |> requester_atlas_user()
    |> Users.has_scope?("admin:write")
  end

  defp requester_atlas_user(opts) do
    case Keyword.get(opts, :requester_atlas_user) do
      %Atlas.Users.User{} = user ->
        user

      _other ->
        opts
        |> Keyword.get(:requester_slack_user)
        |> requester_slack_email()
        |> case do
          email when is_binary(email) -> Users.get_user_by_email(email)
          _email -> nil
        end
    end
  end

  defp requester_slack_email(%User{email: email}) when is_binary(email), do: email
  defp requester_slack_email(_slack_user), do: nil

  @impl true
  def system_prompt do
    """
    You are Atlas in Slack. You help the team answer account, customer,
    sales, support, and product context questions from Atlas data.

    Default behavior:
    - Reply in Slack mrkdwn.
    - Be direct and concise, but include the concrete account details the user
      needs to act.
    - Answer only the question or request that was asked.
    - Do not volunteer follow-up actions, extra process commentary, or requests
      for additional data unless they are required to answer accurately.
    - If the user asks you to stop, be quiet, or leave the thread alone, reply
      with one short acknowledgment and nothing else.
    - If Atlas already sent the latest useful answer in the thread and the new
      message does not ask a new question or add actionable context, return
      exactly [[NO_REPLY]] so Atlas sends no Slack message.
    - Use account tools before answering account-specific questions.
    - If a relevant public URL is shared in the thread and the answer depends
      on its contents, use the fetch_url_content tool before answering.
    - When asked to create a new account, use the create_account tool. New
      accounts should default to prospects unless the requester names another
      lifecycle.
    - If the channel is linked to an account, treat that account as the default
      subject unless the user asks about a different account.
    - If a teammate asks you to capture, save, or note something as a blog post
      idea, use capture_blog_post_idea before replying. Distill a clear title and
      a short description from the thread, then confirm what you captured.
    - If a teammate asks you to capture, save, or note something as a social
      post, social-channel idea, LinkedIn idea, X idea, Bluesky idea, or
      community-channel idea, use capture_social_channel_idea before replying.
      Distill a clear title and a short description from the thread, then
      confirm what you captured.
    - If a teammate asks you to draft, revise, iterate on, or publish a post
      for an existing social-channel idea, use create_social_post_revision or
      update_social_post_revision when those tools are available. Create a new
      revision for substantive edits instead of overwriting the idea notes.
    - If a request needs deeper investigation, delegate it to the
      account_investigator sub-agent and summarize its findings.
    - If a teammate asks about service levels, SLAs, support commitments,
      response times, recovery times, availability, service credits, or
      contractual support obligations, use list_account_service_levels before
      answering.
    - If a request is about company finance, revenue, cash, runway, burn,
      transactions, invoices, or banking, use the available Atlas MCP finance
      tools directly before answering.
    - If a teammate asks you to create a Stripe draft invoice for a customer
      from a signed order form, use create_stripe_draft_invoice. Report the
      source document and draft invoice URL. Do not imply the invoice was
      finalized, sent, or paid. If the tool returns missing_invoice_amount or
      missing_invoice_currency, do not give up: read the order form yourself,
      retry the call with an explicit `line_items` array (each item needs
      description, amount, currency; quantity, period_start, period_end are
      optional), and report which line items you supplied.
    - If a teammate asks you to edit an existing Stripe draft invoice (add or
      fix missing line items, update its description, footer, payment terms,
      or metadata), use edit_stripe_draft_invoice with the Stripe invoice id
      (for example `in_1Abc...`). It re-attaches line items from the latest
      signed order form by default; pass `attach_order_form_line_items: false`
      when the teammate only wants to update invoice fields, or pass an
      explicit `line_items` array to override auto-extraction. Do not direct
      them to Stripe to do it by hand when this tool is available.
    - For month summaries, expense totals, or month-over-month expense
      comparisons, call get_finance_expense_reconciliation for each requested
      period before answering. Treat its `complete` field as authoritative: do
      not state a total as complete when it is false. Use
      list_finance_transactions only to inspect transactions named by that
      reconciliation.
    - For finance transaction detail, avoid exhaustive scans. Prefer one
      credit query and one debit query with small page sizes, then summarize
      the biggest movements and call out uncertainty.
    - If a request is about production systems, infrastructure, metrics,
      incidents, deploys, or Grafana, delegate it to the systems_investigator
      sub-agent when that role is available.
    - For finance questions, do not answer from the lightweight account tools
      alone. Use Atlas MCP finance tools such as get_finance_overview and
      list_finance_transactions before answering.
    - In internal company channels, use search_atlas for broad questions that
      may need account events, outcomes, account summaries, go-to-market
      signals, go-to-market opportunities, blog post ideas, social-channel
      ideas, or channel-approved documents before answering. Only search the
      domains exposed by the tool in the current channel.
    - Do not invent facts. Say what is missing when Atlas does not have enough
      data.
    - Do not apologize repeatedly or narrate your internal process.
    - Never emit [[NO_REPLY]] unless you intend Atlas to stay silent.
    - Prefer bullets and short sections for Slack readability.
    - In internal company channels you have access to a shared memory store.
      Call memory_recall when prior teammate discussions may already hold the
      answer. memory_save *proposes* a memory: it does not persist anything
      until a teammate reacts to the confirmation message Atlas posts in the
      thread. Only propose facts, preferences, decisions, identities, events,
      observations, goals, or todos that are durable and worth carrying into
      future threads. Do not propose sensitive, private, or short-lived
      information (travel logistics, IDs, medical details, lodging,
      individual schedules). After calling memory_save, do not announce the
      proposal in your reply — the confirmation message Atlas posts in the
      thread speaks for itself.

    #{StyleGuide.prose_rules()}
    """
  end

  defp build_mcp_tools(app_key, channel, agent, tool_groups, opts) do
    case mcp_user_and_claims(app_key, channel, agent, tool_groups, opts) do
      {:ok, user, claims} ->
        case MCPTools.tools_for(user, claims) do
          tools when is_list(tools) ->
            tools

          {:error, reason} ->
            Logger.warning("Slack MCP #{agent} access disabled: #{inspect(reason)}")
            []
        end

      {:error, reason} ->
        Logger.warning("Slack MCP #{agent} access disabled: #{inspect(reason)}")
        []
    end
  end

  defp mcp_user_and_claims(app_key, %Channel{} = channel, agent, tool_groups, opts) do
    email = Keyword.get(opts, :mcp_user_email) || slack_agent_mcp_user_email()

    case Users.get_user_by_email(email) do
      %Atlas.Users.User{} = mcp_user ->
        claims = %{
          "scopes" => ["mcp"],
          "mcp_tool_groups" => tool_groups,
          "slack_app" => Atom.to_string(app_key),
          "slack_channel_id" => channel.channel_id,
          "slack_agent" => Atom.to_string(agent)
        }

        {:ok, mcp_user, claims}

      nil ->
        {:error, {:mcp_user_not_found, email}}
    end
  end

  defp slack_agent_mcp_user_email do
    AgentConfig.mcp_user_email(@default_mcp_user_email)
  end

  def build_prompt(event, channel, slack_user, thread_messages \\ [])

  def build_prompt(event, %Channel{} = channel, slack_user, thread_messages) do
    """
    #{memory_bulletin_block(channel.slack_app, channel)}Slack conversation received.

    Conversation:
    - Workspace: #{channel.slack_app}
    - Channel ID: #{channel.channel_id}
    - Thread timestamp: #{event["thread_ts"] || event["ts"]}
    - Message timestamp: #{event["ts"]}
    - User: #{user_display(slack_user, event["user"])}
    - Channel-linked account ID: #{channel.account_id || "-"}

    Thread transcript:
    #{format_thread_transcript(event, thread_messages, slack_user)}
    """
  end

  def build_prompt(event, nil, slack_user, thread_messages) do
    """
    Slack conversation received.

    Conversation:
    - Channel ID: #{event["channel"]}
    - Thread timestamp: #{event["thread_ts"] || event["ts"]}
    - Message timestamp: #{event["ts"]}
    - User: #{user_display(slack_user, event["user"])}
    - Channel-linked account ID: -

    Thread transcript:
    #{format_thread_transcript(event, thread_messages, slack_user)}
    """
  end

  defp memory_bulletin_block(app_key, %Channel{} = channel) do
    with true <- internal_company_channel?(app_key, channel),
         %Bulletin{body: body} <- Memory.get_bulletin(:global),
         trimmed when trimmed != "" <- String.trim(body) do
      "Workspace memory bulletin:\n#{trimmed}\n\n"
    else
      _ -> ""
    end
  end

  def blocks_for_text(text, opts \\ []) when is_binary(text) do
    status = Keyword.get(opts, :status)
    account = Keyword.get(opts, :account)

    []
    |> append_if(branding_block(status))
    |> append_if(account && account_context_block(account))
    |> Kernel.++(text_blocks(text))
  end

  def loading_blocks(status \\ "Thinking") do
    [branding_block(status)]
  end

  def error_blocks(message) do
    blocks_for_text(message, status: "Could not complete the request")
  end

  def account_from_channel(%Channel{account_id: nil}), do: nil

  def account_from_channel(%Channel{account_id: account_id}) do
    Accounts.get_account(account_id)
  end

  def account_from_channel(_), do: nil

  defp find_account_tool do
    Condukt.tool(
      name: "find_account",
      description: "Find Atlas accounts by id, account_key, handle, domain, or name query.",
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string"},
          account_key: %{type: "string"},
          handle: %{type: "string", description: "Account handle such as #acme or a domain alias"},
          query: %{type: "string", description: "Free-text account name, domain, or description query"}
        }
      },
      call: fn params, _ctx ->
        case resolve_or_search_account(params) do
          {:ok, %Account{} = account} ->
            {:ok, serialize_account_summary(account), %{found_account_id: account.id}}

          {:ok, accounts} when is_list(accounts) ->
            {:ok, %{accounts: Enum.map(accounts, &serialize_account_summary/1)}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    )
  end

  defp create_account_tool do
    Condukt.tool(
      name: "create_account",
      description: """
      Create an Atlas account from a Slack request. Use this for requests like
      "create a new account for Acme" or "create an account for Acme as a customer".
      The tool avoids duplicate exact account names and returns the existing
      account instead when one is already present.
      """,
      parameters: %{
        type: "object",
        required: ["name"],
        properties: %{
          name: %{type: "string", minLength: 1, description: "Company or account display name."},
          primary_domain: %{type: "string", description: "Optional primary web domain, such as acme.com."},
          segment: %{
            type: "string",
            enum: ["customer", "lead", "prospect"],
            default: "prospect",
            description: "Lifecycle segment. Defaults to prospect."
          }
        }
      },
      call: fn %{"name" => name} = params, ctx when is_binary(name) ->
        name = String.trim(name)
        segment = Map.get(params, "segment", "prospect") || "prospect"

        case Accounts.get_account_by_name(name) do
          {:ok, %Account{} = account} ->
            {:ok, %{created: false, account: serialize_account_summary(account)}, %{found_account_id: account.id}}

          {:error, :not_found} ->
            attrs =
              %{
                "account_key" => slack_account_key(name),
                "name" => name,
                "segment" => segment,
                "primary_domain" => normalize_domain(Map.get(params, "primary_domain")),
                "metadata" => %{"created_from" => "slack_conversation_agent"}
              }
              |> maybe_put_url_from_domain()

            with_slack_audit(ctx.assigns, fn ->
              case Accounts.create_account(attrs) do
                {:ok, account} ->
                  {:ok, %{created: true, account: serialize_account_summary(account)}, %{found_account_id: account.id}}

                {:error, changeset} ->
                  {:error, "Could not create account: #{ChangesetErrors.format(changeset)}"}
              end
            end)
        end
      end
    )
  end

  defp get_account_context_tool do
    Condukt.tool(
      name: "get_account_context",
      description: """
      Get a full Atlas account context bundle with core fields, contacts,
      invoices, customer outcomes, service-level counts, and recent timeline
      events.
      """,
      parameters: %{
        type: "object",
        properties: AccountLookup.identifier_schema_properties()
      },
      call: fn params, ctx ->
        with {:ok, account} <- resolve_account(params, ctx.assigns),
             %Account{} = account <- Accounts.get_account(account.id) do
          {:ok, serialize_account_context(account), %{found_account_id: account.id}}
        else
          nil -> {:error, "Account not found."}
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end

  defp list_account_service_levels_tool do
    Condukt.tool(
      name: "list_account_service_levels",
      description:
        "List service levels and SLA commitments extracted from signed account documents, including source pages and service credits.",
      parameters: %{
        type: "object",
        properties:
          AccountLookup.identifier_schema_properties()
          |> Map.put("active_on", %{
            type: "string",
            description: "Optional YYYY-MM-DD date to return service levels active on that date."
          })
          |> Map.put("page_size", %{type: "integer", minimum: 1, maximum: @service_level_result_limit})
      },
      call: fn params, ctx ->
        page_size =
          params |> Map.get("page_size", @service_level_result_limit) |> clamp_limit(1, @service_level_result_limit)

        with {:ok, account} <- resolve_account(params, ctx.assigns),
             {:ok, active_on} <- parse_active_on(params["active_on"]) do
          service_levels =
            account
            |> Accounts.list_service_levels(active_on: active_on)
            |> Enum.take(page_size)
            |> Enum.map(&serialize_service_level/1)

          checks =
            account
            |> Accounts.list_service_level_extraction_checks(limit: 5)
            |> Enum.map(&serialize_service_level_extraction_check/1)

          {:ok,
           %{
             account: serialize_account_summary(account),
             service_levels: service_levels,
             service_level_count: length(service_levels),
             service_level_extraction_checks: checks
           }, %{found_account_id: account.id}}
        end
      end
    )
  end

  defp list_account_events_tool do
    Condukt.tool(
      name: "list_account_events",
      description:
        "List recent account timeline events. Use this when investigating recent activity or support context.",
      parameters: %{
        type: "object",
        properties:
          Map.put(AccountLookup.identifier_schema_properties(), :limit, %{type: "integer", minimum: 1, maximum: 50})
      },
      call: fn params, ctx ->
        limit = params |> Map.get("limit", @recent_event_limit) |> clamp_limit(1, 50)

        with {:ok, account} <- resolve_account(params, ctx.assigns),
             %Account{} = account <- Accounts.get_account(account.id) do
          {:ok,
           %{
             account: serialize_account_summary(account),
             events: account.events |> Enum.take(limit) |> Enum.map(&serialize_event/1)
           }, %{found_account_id: account.id}}
        else
          nil -> {:error, "Account not found."}
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end

  defp list_account_outcomes_tool do
    Condukt.tool(
      name: "list_account_outcomes",
      description: "List measurable customer outcomes and their review history for an account.",
      parameters: %{
        type: "object",
        properties:
          Map.put(AccountLookup.identifier_schema_properties(), :statuses, %{
            type: "array",
            items: %{type: "string", enum: ["active", "achieved", "missed", "abandoned"]}
          })
      },
      call: fn params, ctx ->
        statuses = Map.get(params, "statuses")

        with {:ok, account} <- resolve_account(params, ctx.assigns),
             %Account{} = account <- Accounts.get_account(account.id) do
          outcomes =
            account.id
            |> Accounts.list_outcomes(statuses: statuses)
            |> Enum.take(@tool_result_limit)
            |> Enum.map(&serialize_outcome/1)

          {:ok, %{account: serialize_account_summary(account), outcomes: outcomes}, %{found_account_id: account.id}}
        else
          nil -> {:error, "Account not found."}
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end

  defp list_account_outcome_proposals_tool do
    Condukt.tool(
      name: "list_account_outcome_proposals",
      description: "List agent suggestions that are waiting for a teammate to review.",
      parameters: %{
        type: "object",
        properties:
          Map.put(AccountLookup.identifier_schema_properties(), :statuses, %{
            type: "array",
            items: %{type: "string", enum: ["pending", "approved", "rejected"]}
          })
      },
      call: fn params, ctx ->
        statuses = Map.get(params, "statuses", ["pending"])

        with {:ok, account} <- resolve_account(params, ctx.assigns),
             %Account{} = account <- Accounts.get_account(account.id) do
          proposals =
            account
            |> Accounts.list_outcome_proposals(statuses: statuses)
            |> Enum.take(@tool_result_limit)
            |> Enum.map(&serialize_outcome_proposal/1)

          {:ok, %{account: serialize_account_summary(account), proposals: proposals}, %{found_account_id: account.id}}
        else
          nil -> {:error, "Account not found."}
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end

  defp generate_account_outcome_proposals_tool do
    Condukt.tool(
      name: "generate_account_outcome_proposals",
      description:
        "Examine account evidence and create up to three suggestions for teammate review. This never changes customer outcomes directly.",
      parameters: %{
        type: "object",
        properties: AccountLookup.identifier_schema_properties()
      },
      call: fn params, ctx ->
        with {:ok, account} <- resolve_account(params, ctx.assigns) do
          with_slack_audit(ctx.assigns, fn ->
            case Accounts.generate_outcome_proposals(account.id) do
              {:ok, proposals} ->
                {:ok,
                 %{
                   account: serialize_account_summary(account),
                   proposals: Enum.map(proposals, &serialize_outcome_proposal/1)
                 }, %{found_account_id: account.id}}

              {:error, :llm_not_configured} ->
                {:error, "The language model is not configured."}

              {:error, reason} ->
                {:error, "Could not generate suggestions: #{inspect(reason)}"}
            end
          end)
        end
      end
    )
  end

  defp update_account_outcome_proposal_tool do
    Condukt.tool(
      name: "update_account_outcome_proposal",
      description: "Edit a pending customer outcome suggestion after a teammate explicitly requests the change.",
      parameters: %{
        type: "object",
        required: ["proposal_id"],
        properties: %{
          proposal_id: %{type: "string"},
          title: %{type: "string"},
          description: %{type: "string"},
          motion: %{type: "string", enum: Outcome.motions()},
          success_measure: %{type: "string"},
          baseline: %{type: "string"},
          target: %{type: "string"},
          target_date: %{type: "string", format: "date"},
          health: %{type: "string", enum: Outcome.health_values()},
          summary: %{type: "string"},
          recommendation: %{type: "string"},
          rationale: %{type: "string"}
        }
      },
      call: fn %{"proposal_id" => id} = params, ctx ->
        case Accounts.get_outcome_proposal(id) do
          nil ->
            {:error, "Suggestion not found."}

          proposal ->
            attrs =
              Map.take(params, [
                "title",
                "description",
                "motion",
                "success_measure",
                "baseline",
                "target",
                "target_date",
                "health",
                "summary",
                "recommendation",
                "rationale"
              ])

            with_slack_audit(ctx.assigns, fn ->
              case Accounts.update_outcome_proposal(proposal, attrs) do
                {:ok, updated} -> {:ok, %{updated: true, proposal: serialize_outcome_proposal(updated)}}
                {:error, changeset} -> {:error, "Could not update suggestion: #{ChangesetErrors.format(changeset)}"}
              end
            end)
        end
      end
    )
  end

  defp approve_account_outcome_proposal_tool do
    Condukt.tool(
      name: "approve_account_outcome_proposal",
      description:
        "Approve a pending suggestion and apply it to the account. Use only after a teammate explicitly asks for approval.",
      parameters: %{
        type: "object",
        required: ["proposal_id"],
        properties: %{proposal_id: %{type: "string"}}
      },
      call: fn %{"proposal_id" => id}, ctx ->
        case Accounts.get_outcome_proposal(id) do
          nil ->
            {:error, "Suggestion not found."}

          proposal ->
            with_slack_audit(ctx.assigns, fn ->
              case Accounts.approve_outcome_proposal(proposal) do
                {:ok, result} ->
                  {:ok,
                   %{
                     approved: true,
                     proposal: serialize_outcome_proposal(result.proposal),
                     outcome: serialize_outcome(result.outcome)
                   }}

                {:error, reason} ->
                  {:error, "Could not approve suggestion: #{format_proposal_error(reason)}"}
              end
            end)
        end
      end
    )
  end

  defp reject_account_outcome_proposal_tool do
    Condukt.tool(
      name: "reject_account_outcome_proposal",
      description:
        "Reject a pending suggestion and preserve the teammate's reason so it is not proposed again without new evidence.",
      parameters: %{
        type: "object",
        required: ["proposal_id", "reason"],
        properties: %{
          proposal_id: %{type: "string"},
          reason: %{type: "string", minLength: 1}
        }
      },
      call: fn %{"proposal_id" => id, "reason" => reason}, ctx ->
        case Accounts.get_outcome_proposal(id) do
          nil ->
            {:error, "Suggestion not found."}

          proposal ->
            with_slack_audit(ctx.assigns, fn ->
              case Accounts.reject_outcome_proposal(proposal, reason) do
                {:ok, rejected} -> {:ok, %{rejected: true, proposal: serialize_outcome_proposal(rejected)}}
                {:error, changeset} -> {:error, "Could not reject suggestion: #{ChangesetErrors.format(changeset)}"}
              end
            end)
        end
      end
    )
  end

  defp atlas_search_tool(allowed_domains) do
    Condukt.tool(
      name: "search_atlas",
      description:
        "Search channel-approved Atlas domains, including indexed account events, customer outcomes, account summaries, go-to-market opportunities, go-to-market signals, blog post ideas, and documents when this channel has document access.",
      parameters: %{
        type: "object",
        required: ["query"],
        properties: %{
          query: %{type: "string", minLength: 1, description: "Natural-language search query."},
          domains: %{
            type: "array",
            items: %{type: "string", enum: allowed_domains},
            description: "Optional. Restrict search to channel-approved domains."
          },
          source_types: %{
            type: "array",
            items: %{type: "string", enum: FederatedSearch.source_types()},
            description: "Optional. Restrict search to specific indexed resource types."
          },
          account_id: %{type: "string", description: "Optional. Restrict results to one Atlas account."},
          max_results: %{type: "integer", minimum: 1, maximum: @tool_result_limit}
        }
      },
      call: fn params, _ctx ->
        with {:ok, query} <- parse_search_query(params["query"]) do
          limit = params |> Map.get("max_results", @tool_result_limit) |> clamp_limit(1, @tool_result_limit)

          opts =
            [limit: limit, allowed_domains: allowed_domains]
            |> maybe_put(:domains, Map.get(params, "domains"))
            |> maybe_put(:source_types, Map.get(params, "source_types"))
            |> maybe_put(:account_id, Map.get(params, "account_id"))

          FederatedSearch.search(query, opts)
        end
      end
    )
  end

  defp review_account_outcome_tool do
    Condukt.tool(
      name: "review_account_outcome",
      description: "Record evidence-based health and the recommended next move for a customer outcome.",
      parameters: %{
        type: "object",
        required: ["outcome_id", "health", "summary"],
        properties: %{
          outcome_id: %{type: "string"},
          health: %{type: "string", enum: ["unknown", "on_track", "at_risk", "off_track"]},
          summary: %{type: "string"},
          evidence: %{type: "array", items: %{type: "string"}},
          recommendation: %{type: "string"}
        }
      },
      call: fn params, ctx ->
        with_slack_audit(ctx.assigns, fn ->
          case Accounts.get_outcome(params["outcome_id"]) do
            nil ->
              {:error, "Outcome not found."}

            outcome ->
              attrs = %{
                "health" => params["health"],
                "summary" => params["summary"],
                "evidence" => %{"items" => Map.get(params, "evidence", [])},
                "recommendation" => params["recommendation"]
              }

              case Accounts.create_outcome_review(outcome, attrs) do
                {:ok, review} ->
                  {:ok,
                   %{reviewed: true, outcome: serialize_outcome(Accounts.get_outcome(outcome.id)), review_id: review.id}}

                {:error, changeset} ->
                  {:error, "Could not review outcome: #{ChangesetErrors.format(changeset)}"}
              end
          end
        end)
      end
    )
  end

  defp capture_blog_post_idea_tool do
    Condukt.tool(
      name: "capture_blog_post_idea",
      description: """
      Capture a blog post idea in the Atlas GTM content backlog. Use this when a
      teammate asks Atlas to capture, save, or note something as a blog post idea,
      for example "capture this as a blog post idea" or "save a blog idea about X".
      Distill a clear title and a short description from the thread.
      """,
      parameters: %{
        type: "object",
        required: ["title"],
        properties: %{
          title: %{type: "string", minLength: 1, description: "Short, specific headline for the idea."},
          description: %{
            type: "string",
            description: "The angle, audience, and takeaway, drawn from the thread."
          }
        }
      },
      call: fn %{"title" => title} = params, ctx when is_binary(title) ->
        attrs =
          %{
            "title" => title,
            "description" => Map.get(params, "description"),
            "created_by_agent" => "slack"
          }

        with_slack_audit(ctx.assigns, fn ->
          case GTM.create_blog_post_idea(attrs, nil, announce: true) do
            {:ok, idea} ->
              {:ok, %{captured: true, blog_post_idea: serialize_blog_post_idea(idea)}}

            {:error, changeset} ->
              {:error, "Could not capture blog post idea: #{ChangesetErrors.format(changeset)}"}
          end
        end)
      end
    )
  end

  defp capture_social_channel_idea_tool do
    Condukt.tool(
      name: "capture_social_channel_idea",
      description: """
      Capture a social-channel idea in the Atlas go-to-market content backlog.
      Use this when a teammate asks Atlas to capture, save, or note something as
      a social post idea, social-channel idea, LinkedIn idea, X idea, Bluesky
      idea, or community-channel idea. Distill a clear title and a short
      description from the thread.
      """,
      parameters: %{
        type: "object",
        required: ["title"],
        properties: %{
          title: %{type: "string", minLength: 1, description: "Short, specific headline for the idea."},
          description: %{
            type: "string",
            description: "The angle, source material, and desired takeaway, drawn from the thread."
          }
        }
      },
      call: fn %{"title" => title} = params, ctx when is_binary(title) ->
        attrs =
          %{
            "title" => title,
            "description" => Map.get(params, "description"),
            "created_by_agent" => "slack"
          }

        with_slack_audit(ctx.assigns, fn ->
          case GTM.create_social_channel_idea(attrs, nil) do
            {:ok, idea} ->
              {:ok, %{captured: true, social_channel_idea: serialize_social_channel_idea(idea)}}

            {:error, changeset} ->
              {:error, "Could not capture social-channel idea: #{ChangesetErrors.format(changeset)}"}
          end
        end)
      end
    )
  end

  defp list_social_channel_ideas_tool do
    Condukt.tool(
      name: "list_social_channel_ideas",
      description: """
      List social-channel ideas from the go-to-market content backlog. Use this
      before drafting, revising, or publishing a post when the teammate refers
      to an existing idea without giving its ID.
      """,
      parameters: %{
        type: "object",
        properties: %{
          status: %{
            type: "string",
            enum: ["idea", "approved"],
            description: "Optional status filter."
          }
        }
      },
      call: fn params, _ctx ->
        ideas =
          GTM.list_social_channel_ideas()
          |> maybe_filter_social_channel_idea_status(Map.get(params, "status"))
          |> Enum.map(&GTMSerializer.social_channel_idea/1)

        {:ok, %{social_channel_ideas: ideas, count: length(ideas)}}
      end
    )
  end

  defp get_social_channel_idea_tool do
    Condukt.tool(
      name: "get_social_channel_idea",
      description: "Get a social-channel idea with its post revisions.",
      parameters: %{
        type: "object",
        required: ["social_channel_idea_id"],
        properties: %{
          social_channel_idea_id: %{type: "string", minLength: 1}
        }
      },
      call: fn %{"social_channel_idea_id" => id}, _ctx ->
        case GTM.get_social_channel_idea(id) do
          nil ->
            {:error, "Social-channel idea not found."}

          idea ->
            {:ok, %{social_channel_idea: GTMSerializer.social_channel_idea_with_post_revisions(idea)}}
        end
      end
    )
  end

  defp create_social_post_revision_tool do
    Condukt.tool(
      name: "create_social_post_revision",
      description: """
      Add a draft or approved post revision to a social-channel idea from a
      Slack request. Use this for substantive post drafts and revisions.
      """,
      parameters: %{
        type: "object",
        required: ["social_channel_idea_id", "body"],
        properties: %{
          social_channel_idea_id: %{type: "string", minLength: 1},
          body: %{type: "string", minLength: 1, description: "The social post text."},
          notes: %{type: "string", description: "Optional note about this revision."},
          status: %{type: "string", enum: ["draft", "approved"], default: "draft"}
        }
      },
      call: fn %{"social_channel_idea_id" => id} = params, ctx ->
        case Map.get(params, "body") do
          body when is_binary(body) and body != "" ->
            case GTM.get_social_channel_idea(id) do
              nil ->
                {:error, "Social-channel idea not found."}

              idea ->
                attrs =
                  params
                  |> Map.take(["body", "notes", "status"])
                  |> Map.put("created_by_agent", "slack")

                with_slack_audit(ctx.assigns, fn ->
                  case GTM.create_social_post_revision(idea, attrs, nil, actor: nil) do
                    {:ok, revision} ->
                      {:ok, %{created: true, social_post_revision: GTMSerializer.social_post_revision(revision)}}

                    {:error, changeset} ->
                      {:error, "Could not create social post revision: #{ChangesetErrors.format(changeset)}"}
                  end
                end)
            end

          _ ->
            {:error, "A non-empty body is required to create a social post revision."}
        end
      end
    )
  end

  defp update_social_post_revision_tool do
    Condukt.tool(
      name: "update_social_post_revision",
      description: """
      Update a social post revision from Slack, including marking it as
      approved when the teammate says the post is ready or already approved.
      """,
      parameters: %{
        type: "object",
        required: ["social_post_revision_id"],
        properties: %{
          social_post_revision_id: %{type: "string", minLength: 1},
          body: %{type: "string", description: "Updated social post text."},
          notes: %{type: "string", description: "Optional note about this revision."},
          status: %{type: "string", enum: ["draft", "approved"]}
        }
      },
      call: fn %{"social_post_revision_id" => id} = params, ctx ->
        case GTM.get_social_post_revision(id) do
          nil ->
            {:error, "Social post revision not found."}

          revision ->
            attrs = Map.take(params, ["body", "notes", "status"])

            with_slack_audit(ctx.assigns, fn ->
              case GTM.update_social_post_revision(revision, attrs, actor: nil) do
                {:ok, updated} ->
                  {:ok, %{updated: true, social_post_revision: GTMSerializer.social_post_revision(updated)}}

                {:error, changeset} ->
                  {:error, "Could not update social post revision: #{ChangesetErrors.format(changeset)}"}
              end
            end)
        end
      end
    )
  end

  defp maybe_filter_social_channel_idea_status(ideas, status) when status in ["idea", "approved"] do
    Enum.filter(ideas, &(&1.status == status))
  end

  defp maybe_filter_social_channel_idea_status(ideas, _status), do: ideas

  defp serialize_blog_post_idea(idea) do
    %{
      id: idea.id,
      title: idea.title,
      description: idea.description,
      status: idea.status
    }
  end

  defp serialize_social_channel_idea(idea) do
    %{
      id: idea.id,
      title: idea.title,
      description: idea.description,
      status: idea.status
    }
  end

  defp with_slack_audit(assigns, fun) when is_function(fun, 0) do
    Audit.with_context(slack_audit_context(assigns), fun)
  end

  defp slack_audit_context(assigns) when is_map(assigns) do
    slack_user = Map.get(assigns, :requester_slack_user) || Map.get(assigns, "requester_slack_user")

    %{
      interface: "slack",
      actor_email: slack_user && slack_user.email,
      actor_name: slack_user && User.best_display_name(slack_user)
    }
  end

  defp slack_audit_context(_assigns), do: %{interface: "slack"}

  defp resolve_or_search_account(params) do
    case account_identifier(params) do
      nil ->
        search_accounts(Map.get(params, "query"))

      identifier ->
        AccountLookup.resolve(identifier)
    end
  end

  defp resolve_account(params, assigns) do
    case account_identifier(params) do
      nil ->
        case Map.get(assigns, :found_account_id) do
          id when is_binary(id) -> AccountLookup.resolve(%{"account_id" => id})
          _ -> {:error, "Provide an account identifier or call find_account first."}
        end

      identifier ->
        AccountLookup.resolve(identifier)
    end
  end

  defp account_identifier(params) do
    ["account_id", "account_key", "handle"]
    |> Enum.find_value(fn key ->
      value = params[key]
      if present?(value), do: %{key => value}
    end)
  end

  defp search_accounts(query) when is_binary(query) do
    accounts =
      Account
      |> where(
        [account],
        ilike(account.name, ^"%#{query}%") or
          ilike(coalesce(account.primary_domain, ""), ^"%#{query}%") or
          ilike(coalesce(account.description, ""), ^"%#{query}%")
      )
      |> order_by([account], asc: account.name)
      |> limit(5)
      |> Repo.all()

    case accounts do
      [] -> {:error, "No accounts matched #{inspect(query)}."}
      [account] -> {:ok, account}
      accounts -> {:ok, accounts}
    end
  end

  defp search_accounts(_), do: {:error, "Provide an account identifier or query."}

  defp parse_active_on(nil), do: {:ok, nil}
  defp parse_active_on(""), do: {:ok, nil}

  defp parse_active_on(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "active_on must be a YYYY-MM-DD date."}
    end
  end

  defp parse_active_on(_value), do: {:error, "active_on must be a YYYY-MM-DD date."}

  defp parse_search_query(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "query is required."}
      query -> {:ok, query}
    end
  end

  defp parse_search_query(_value), do: {:error, "query is required."}

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_domain(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/^https?:\/\//i, "")
    |> String.split("/", parts: 2)
    |> List.first()
    |> String.downcase()
    |> case do
      "" -> nil
      domain -> domain
    end
  end

  defp normalize_domain(_value), do: nil

  defp maybe_put_url_from_domain(%{"primary_domain" => domain} = attrs) when is_binary(domain) do
    Map.put(attrs, "url", "https://" <> domain)
  end

  defp maybe_put_url_from_domain(attrs), do: attrs

  defp slack_account_key(name), do: "slack:#{slugify(name)}"

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "account"
      slug -> slug
    end
  end

  defp serialize_account_context(%Account{} = account) do
    %{
      account: serialize_account_summary(account),
      contacts: account.contacts |> Enum.take(@tool_result_limit) |> Enum.map(&serialize_contact/1),
      invoices: account.invoices |> Enum.take(@tool_result_limit) |> Enum.map(&serialize_invoice/1),
      outcomes: account.outcomes |> Enum.take(@tool_result_limit) |> Enum.map(&serialize_outcome/1),
      outcome_proposals:
        account.outcome_proposals
        |> Enum.filter(&(&1.status == "pending"))
        |> Enum.take(@tool_result_limit)
        |> Enum.map(&serialize_outcome_proposal/1),
      service_level_count: length(account.service_levels),
      recent_events: account.events |> Enum.take(@recent_event_limit) |> Enum.map(&serialize_event/1)
    }
  end

  defp serialize_account_summary(%Account{} = account) do
    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      segment: format_value(account.segment),
      deal_stage: format_value(account.deal_stage),
      status: account.status,
      current_value: Amounts.format_or_nil(account.current_value, account.currency),
      next_renewal_date: format_value(account.next_renewal_date),
      primary_domain: account.primary_domain,
      overview_summary: account.overview_summary,
      latest_activity_at: format_value(account.latest_activity_at)
    }
  end

  defp serialize_contact(contact) do
    %{name: contact.full_name, email: contact.email, title: contact.title}
  end

  defp serialize_invoice(invoice) do
    %{
      number: invoice.number,
      due_date: format_value(invoice.due_date),
      amount: Amounts.format_or_nil(invoice.amount_value, invoice.amount_currency),
      status: invoice.status,
      stripe_url: invoice.stripe_url
    }
  end

  defp serialize_outcome(outcome) do
    %{
      id: outcome.id,
      account_id: outcome.account_id,
      title: outcome.title,
      description: outcome.description,
      status: outcome.status,
      health: outcome.health,
      motion: outcome.motion,
      success_measure: outcome.success_measure,
      baseline: outcome.baseline,
      target: outcome.target,
      target_date: format_value(outcome.target_date),
      reviewed_at: format_value(outcome.reviewed_at),
      latest_review: serialize_latest_outcome_review(outcome)
    }
  end

  defp serialize_outcome_proposal(proposal) do
    %{
      id: proposal.id,
      account_id: proposal.account_id,
      outcome_id: proposal.outcome_id,
      proposal_type: proposal.proposal_type,
      status: proposal.status,
      title: proposal.title,
      description: proposal.description,
      motion: proposal.motion,
      success_measure: proposal.success_measure,
      baseline: proposal.baseline,
      target: proposal.target,
      target_date: format_value(proposal.target_date),
      health: proposal.health,
      summary: proposal.summary,
      recommendation: proposal.recommendation,
      evidence: proposal.evidence,
      confidence: format_value(proposal.confidence),
      rationale: proposal.rationale,
      rejection_reason: proposal.rejection_reason,
      reviewed_at: format_value(proposal.reviewed_at)
    }
  end

  defp serialize_latest_outcome_review(%{reviews: [review | _reviews]}) do
    %{
      health: review.health,
      summary: review.summary,
      evidence: review.evidence,
      recommendation: review.recommendation,
      reviewed_at: format_value(review.reviewed_at)
    }
  end

  defp serialize_latest_outcome_review(_outcome), do: nil

  defp format_proposal_error(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.replace("_", " ")
  defp format_proposal_error(reason), do: inspect(reason)

  defp serialize_service_level(service_level) do
    %{
      id: service_level.id,
      name: service_level.name,
      category: service_level.category,
      target: service_level.target,
      measurement_window: service_level.measurement_window,
      applies_from: format_value(service_level.applies_from),
      applies_until: format_value(service_level.applies_until),
      service_credit: service_level.service_credit,
      exclusions: service_level.exclusions,
      source_page: service_level.source_page,
      source_excerpt: service_level.source_excerpt,
      document_title: service_level_document_title(service_level),
      document_id: service_level.document_id
    }
  end

  defp serialize_service_level_extraction_check(check) do
    %{
      id: check.id,
      status: check.status,
      document_title: service_level_document_title(check),
      completed_at: format_value(check.completed_at),
      result_summary: check.result_summary,
      last_error: check.last_error
    }
  end

  defp service_level_document_title(%{document: %{title: title}}) when is_binary(title), do: title
  defp service_level_document_title(_record), do: nil

  defp serialize_event(event) do
    %{
      id: event.id,
      source: event.source,
      kind: event.kind,
      title: event.title,
      body: event.body,
      occurred_at: format_value(event.occurred_at),
      url: event.url
    }
  end

  defp account_context_block(%Account{} = account) do
    fields =
      [
        {"Account", account.name},
        {"Lifecycle", format_value(account.segment)},
        {"Value", Amounts.format_or_nil(account.current_value, account.currency)}
      ]
      |> Enum.reject(fn {_label, value} -> !present?(value) end)
      |> Enum.map(fn {label, value} -> %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape_mrkdwn(value)}"} end)

    if fields != [] do
      %{"type" => "section", "fields" => fields}
    end
  end

  defp branding_block(status) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "image", "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png", "alt_text" => "Atlas"},
        %{"type" => "mrkdwn", "text" => "*Atlas* · #{escape_mrkdwn(status || "Slack agent")}"}
      ]
    }
  end

  defp text_blocks(text) do
    text
    |> split_text(2800)
    |> Enum.map(fn chunk ->
      %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => chunk}}
    end)
  end

  defp split_text(text, max_length) do
    text
    |> String.trim()
    |> case do
      "" -> ["Working on it..."]
      text -> do_split_text(text, max_length, [])
    end
  end

  defp do_split_text("", _max_length, acc), do: Enum.reverse(acc)

  defp do_split_text(text, max_length, acc) do
    {chunk, rest} = String.split_at(text, max_length)
    do_split_text(rest, max_length, [chunk | acc])
  end

  defp append_if(blocks, nil), do: blocks
  defp append_if(blocks, block), do: blocks ++ [block]

  defp format_thread_transcript(event, thread_messages, slack_user) do
    event
    |> merged_thread_messages(thread_messages)
    |> Enum.map_join("\n", fn thread_message ->
      author = thread_message_author(thread_message, slack_user, event["user"])
      text = thread_message_text(thread_message, event)
      "- #{author}: #{text}"
    end)
  end

  defp merged_thread_messages(event, thread_messages) do
    [event_as_thread_message(event) | thread_messages]
    |> Enum.uniq_by(&thread_message_ts/1)
    |> Enum.sort_by(&slack_ts_sort_key(thread_message_ts(&1)))
  end

  defp event_as_thread_message(event) do
    %{
      user_id: event["user"],
      text: event["text"] || "",
      ts: event["ts"],
      thread_ts: event["thread_ts"] || event["ts"]
    }
  end

  defp thread_message_author(%{user_id: user_id}, %User{} = slack_user, current_user_id)
       when user_id == current_user_id do
    user_display(slack_user, user_id)
  end

  defp thread_message_author(%{"user_id" => user_id}, %User{} = slack_user, current_user_id)
       when user_id == current_user_id do
    user_display(slack_user, user_id)
  end

  defp thread_message_author(%{username: username}, _slack_user, _current_user_id)
       when is_binary(username) and username != "", do: username

  defp thread_message_author(%{"username" => username}, _slack_user, _current_user_id)
       when is_binary(username) and username != "", do: username

  defp thread_message_author(%{user_id: user_id}, _slack_user, _current_user_id)
       when is_binary(user_id) and user_id != "", do: user_id

  defp thread_message_author(%{"user_id" => user_id}, _slack_user, _current_user_id)
       when is_binary(user_id) and user_id != "", do: user_id

  defp thread_message_author(%{bot_id: bot_id}, _slack_user, _current_user_id) when is_binary(bot_id) and bot_id != "",
    do: "Atlas"

  defp thread_message_author(%{"bot_id" => bot_id}, _slack_user, _current_user_id)
       when is_binary(bot_id) and bot_id != "", do: "Atlas"

  defp thread_message_author(_thread_message, _slack_user, _current_user_id), do: "Unknown"

  defp thread_message_text(thread_message, event) do
    text =
      thread_message
      |> thread_message_value(:text, "")
      |> clean_message_text(event["atlas_authorized_user_ids"] || [])

    if text == "" do
      "(no text)"
    else
      text
    end
  end

  defp clean_message_text(text, authorized_user_ids) when is_binary(text) and is_list(authorized_user_ids) do
    text =
      case Enum.filter(authorized_user_ids, &is_binary/1) do
        [] ->
          String.replace(text, ~r/<@[A-Za-z0-9]+>\s*/, "")

        bot_user_ids ->
          Enum.reduce(bot_user_ids, text, fn user_id, acc ->
            String.replace(acc, ~r/<@#{Regex.escape(user_id)}>\s*/, "")
          end)
      end

    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clean_message_text(_text, _authorized_user_ids), do: ""

  defp thread_message_ts(thread_message), do: thread_message_value(thread_message, :ts, nil)

  defp thread_message_value(thread_message, key, default) when is_map(thread_message) do
    Map.get(thread_message, key) || Map.get(thread_message, Atom.to_string(key)) ||
      get_in(thread_message, ["raw", Atom.to_string(key)]) || default
  end

  defp thread_message_value(_thread_message, _key, default), do: default

  defp slack_ts_sort_key(ts) when is_binary(ts) do
    case String.split(ts, ".", parts: 2) do
      [seconds, micros] ->
        {parse_int(seconds), parse_int(String.pad_trailing(micros, 6, "0"))}

      [seconds] ->
        {parse_int(seconds), 0}

      _parts ->
        {0, 0}
    end
  end

  defp slack_ts_sort_key(_ts), do: {0, 0}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed
      :error -> 0
    end
  end

  defp account_investigator_prompt do
    """
    You are an Atlas sub-agent for deeper account investigations.
    Use the account tools to gather relevant context, then return a compact
    finding with evidence, likely explanation, and next steps. Stay grounded
    in Atlas data and call out uncertainty.
    """
  end

  defp systems_investigator_prompt do
    """
    You are an Atlas systems sub-agent for production-system investigations.
    Use the MCP tools to inspect Atlas and upstream systems such as Grafana.
    Prefer read-only investigation. Return a concise finding with evidence,
    likely impact, and concrete next steps. Do not change production state
    unless the Slack user explicitly asks for that action.

    Finance requests should be answered by the main Slack agent with Atlas MCP
    finance tools. Focus this sub-agent on production-system and infrastructure
    investigations unless the user explicitly asks to correlate finance data
    with operational evidence.
    """
  end

  defp clamp_limit(value, min, max) when is_integer(value), do: value |> Kernel.max(min) |> Kernel.min(max)
  defp clamp_limit(_value, _min, max), do: max

  defp user_display(%User{} = user, _fallback), do: User.best_display_name(user)
  defp user_display(_user, fallback) when is_binary(fallback), do: fallback
  defp user_display(_user, _fallback), do: "-"

  defp format_value(nil), do: nil
  defp format_value(%Date{} = date), do: Date.to_iso8601(date)
  defp format_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: to_string(value)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp escape_mrkdwn(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
