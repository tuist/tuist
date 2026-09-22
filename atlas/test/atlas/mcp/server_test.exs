defmodule Atlas.MCP.ServerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.Users
  alias Atlas.Users.User

  setup :verify_on_exit!

  test "hoists upstream tools into tools/list" do
    expect(Proxy, :list_hoisted_tools, fn nil ->
      [
        %{
          "name" => "grafana__search_dashboards",
          "description" => "[grafana] Search Grafana dashboards",
          "inputSchema" => %{"type" => "object", "properties" => %{}},
          "_meta" => %{
            "atlas/proxyServer" => "grafana",
            "atlas/originalToolName" => "search_dashboards"
          }
        }
      ]
    end)

    response =
      Server.handle_message(nil, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      })

    tools = response["result"]["tools"]

    assert Enum.any?(tools, &(&1["name"] == "get_mcp_connection_status"))
    assert Enum.any?(tools, &(&1["name"] == "list_accounts"))
    assert Enum.any?(tools, &(&1["name"] == "list_account_attention_suggestions"))
    assert Enum.any?(tools, &(&1["name"] == "list_account_nudges"))
    assert Enum.any?(tools, &(&1["name"] == "claim_nudge"))
    assert Enum.any?(tools, &(&1["name"] == "dismiss_nudge"))
    refute Enum.any?(tools, &(&1["name"] == "list_account_outcomes"))
    refute Enum.any?(tools, &(&1["name"] == "generate_account_outcome_proposals"))
    assert Enum.any?(tools, &(&1["name"] == "create_account"))
    assert Enum.any?(tools, &(&1["name"] == "mark_account_not_account"))
    assert Enum.any?(tools, &(&1["name"] == "list_upcoming_renewals"))
    assert Enum.any?(tools, &(&1["name"] == "list_finance_categories"))
    assert Enum.any?(tools, &(&1["name"] == "list_finance_transactions"))
    assert Enum.any?(tools, &(&1["name"] == "get_finance_expense_reconciliation"))
    assert Enum.any?(tools, &(&1["name"] == "create_stripe_draft_invoice"))
    assert Enum.any?(tools, &(&1["name"] == "edit_stripe_draft_invoice"))
    assert Enum.any?(tools, &(&1["name"] == "list_social_channel_ideas"))
    assert Enum.any?(tools, &(&1["name"] == "get_social_channel_idea"))
    assert Enum.any?(tools, &(&1["name"] == "create_social_channel_idea"))
    assert Enum.any?(tools, &(&1["name"] == "update_social_channel_idea"))
    assert Enum.any?(tools, &(&1["name"] == "delete_social_channel_idea"))
    assert Enum.any?(tools, &(&1["name"] == "list_social_post_revisions"))
    assert Enum.any?(tools, &(&1["name"] == "get_social_post_revision"))
    assert Enum.any?(tools, &(&1["name"] == "create_social_post_revision"))
    assert Enum.any?(tools, &(&1["name"] == "update_social_post_revision"))
    assert Enum.any?(tools, &(&1["name"] == "delete_social_post_revision"))
    assert Enum.any?(tools, &(&1["name"] == "generate_enterprise_contract"))
    assert Enum.any?(tools, &(&1["name"] == "list_contract_templates"))
    assert Enum.any?(tools, &(&1["name"] == "get_contract_template"))
    assert Enum.any?(tools, &(&1["name"] == "delete_email_audience"))

    assert %{
             "name" => "grafana__search_dashboards",
             "description" => "[grafana] Search Grafana dashboards",
             "_meta" => %{
               "atlas/proxyServer" => "grafana",
               "atlas/originalToolName" => "search_dashboards"
             }
           } = Enum.find(tools, &(&1["name"] == "grafana__search_dashboards"))
  end

  test "advertises an output schema for every static tool" do
    stub(Proxy, :list_hoisted_tools, fn nil -> [] end)

    response = Server.handle_message(nil, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})

    for tool <- response["result"]["tools"] do
      assert %{"type" => "object"} = tool["outputSchema"], "tool #{tool["name"]} does not advertise an output schema"
    end
  end

  test "passes hoisted tools through tools/list without inventing an output schema" do
    stub(Proxy, :list_hoisted_tools, fn nil ->
      [%{"name" => "grafana__search_dashboards", "inputSchema" => %{"type" => "object"}}]
    end)

    response = Server.handle_message(nil, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})

    hoisted = Enum.find(response["result"]["tools"], &(&1["name"] == "grafana__search_dashboards"))

    refute Map.has_key?(hoisted, "outputSchema")
  end

  describe "initialize" do
    test "echoes back a protocol version the client asked for and we support" do
      response =
        Server.handle_message(nil, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2025-03-26"}
        })

      assert response["result"]["protocolVersion"] == "2025-03-26"
    end

    test "advertises the revision that introduced structured content by default" do
      response = Server.handle_message(nil, %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

      assert response["result"]["protocolVersion"] == "2025-06-18"
    end

    test "instructs clients to use Atlas for order forms instead of drafting substitutes" do
      response = Server.handle_message(nil, %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

      instructions = response["result"]["instructions"]

      assert instructions =~ "create, draft, prepare, generate, or fill an order form"
      assert instructions =~ "generate_enterprise_contract"
      assert instructions =~ "get_account"
      assert instructions =~ "list_contract_templates"
      assert instructions =~ "get_contract_template"
      assert instructions =~ "Never create a substitute document from scratch"
      assert instructions =~ "embedded resource"
      assert instructions =~ "current request over pasted conversation context"
    end

    test "falls back to the newest supported revision when the client asks for one we do not speak" do
      response =
        Server.handle_message(nil, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2024-11-05"}
        })

      assert response["result"]["protocolVersion"] == "2025-06-18"
    end
  end

  test "dispatches hoisted tools through the upstream server" do
    expect(Proxy, :call_hoisted_tool, fn nil, "grafana__query_prometheus", %{"query" => "up"} ->
      {:ok, %{"content" => [%{"type" => "text", "text" => "ok"}]}}
    end)

    response =
      Server.handle_message(nil, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "grafana__query_prometheus",
          "arguments" => %{"query" => "up"}
        }
      })

    assert response == %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{"content" => [%{"type" => "text", "text" => "ok"}]}
           }
  end

  test "filters finance tools from restricted MCP sessions without finance access" do
    conn = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => []}}}

    expect(Proxy, :list_hoisted_tools, fn ^conn -> [] end)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      })

    tools = response["result"]["tools"]

    refute Enum.any?(tools, &(&1["name"] == "list_finance_transactions"))
    refute Enum.any?(tools, &(&1["name"] == "get_finance_expense_reconciliation"))
    refute Enum.any?(tools, &(&1["name"] == "get_finance_overview"))
    refute Enum.any?(tools, &(&1["name"] == "create_stripe_draft_invoice"))
    refute Enum.any?(tools, &(&1["name"] == "edit_stripe_draft_invoice"))
    assert Enum.any?(tools, &(&1["name"] == "list_accounts"))
  end

  test "keeps contract term tools available to restricted MCP sessions" do
    # Slack agent sessions are restricted (they carry mcp_tool_groups). Contract
    # term CRUD lives in the default group so it reaches those sessions like the
    # sibling account write tools (create_contact, update_account, ...).
    conn = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => []}}}

    expect(Proxy, :list_hoisted_tools, fn ^conn -> [] end)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      })

    tools = response["result"]["tools"]

    assert Enum.any?(tools, &(&1["name"] == "list_account_terms"))
    assert Enum.any?(tools, &(&1["name"] == "create_account_term"))
    assert Enum.any?(tools, &(&1["name"] == "update_account_term"))
    assert Enum.any?(tools, &(&1["name"] == "delete_account_term"))
  end

  test "rejects finance tool calls from restricted MCP sessions without finance access" do
    conn = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => []}}}

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "list_finance_transactions",
          "arguments" => %{}
        }
      })

    assert response["error"]["message"] =~ "not available"
  end

  test "keeps finance tools available when restricted MCP session includes finance access" do
    conn = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => ["finance"]}}}

    expect(Proxy, :list_hoisted_tools, fn ^conn -> [] end)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      })

    tools = response["result"]["tools"]

    assert Enum.any?(tools, &(&1["name"] == "list_finance_transactions"))
    assert Enum.any?(tools, &(&1["name"] == "get_finance_expense_reconciliation"))
    assert Enum.any?(tools, &(&1["name"] == "get_finance_overview"))
    assert Enum.any?(tools, &(&1["name"] == "create_stripe_draft_invoice"))
    assert Enum.any?(tools, &(&1["name"] == "edit_stripe_draft_invoice"))
  end

  test "hides audit tools from MCP sessions without admin scope" do
    conn = %{assigns: %{current_user: %User{}}}

    stub(Users, :has_scope?, fn %User{}, "admin:read" -> false end)
    expect(Proxy, :list_hoisted_tools, fn ^conn -> [] end)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      })

    tools = response["result"]["tools"]

    refute Enum.any?(tools, &(&1["name"] == "list_audit_activities"))
    refute Enum.any?(tools, &(&1["name"] == "get_audit_activity"))
    refute Enum.any?(tools, &(&1["name"] == "list_licenses"))
    refute Enum.any?(tools, &(&1["name"] == "create_license"))
    refute Enum.any?(tools, &(&1["name"] == "extend_license"))
    refute Enum.any?(tools, &(&1["name"] == "check_out_air_gapped_license"))
    refute Enum.any?(tools, &(&1["name"] == "request_tax_certificate_letter"))
    refute Enum.any?(tools, &(&1["name"] == "create_letter_document_upload"))
    refute Enum.any?(tools, &(&1["name"] == "finalize_letter_document_upload"))
    refute Enum.any?(tools, &(&1["name"] == "confirm_tax_certificate_delivery"))
    refute Enum.any?(tools, &(&1["name"] == "list_account_letters"))
    refute Enum.any?(tools, &(&1["name"] == "check_letter_delivery"))
  end

  test "shows audit tools to MCP sessions with admin scope" do
    conn = %{assigns: %{current_user: %User{}}}

    stub(Users, :has_scope?, fn %User{}, "admin:read" -> true end)
    expect(Proxy, :list_hoisted_tools, fn ^conn -> [] end)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      })

    tools = response["result"]["tools"]

    assert Enum.any?(tools, &(&1["name"] == "list_audit_activities"))
    assert Enum.any?(tools, &(&1["name"] == "get_audit_activity"))
    assert Enum.any?(tools, &(&1["name"] == "list_licenses"))
    assert Enum.any?(tools, &(&1["name"] == "create_license"))
    assert Enum.any?(tools, &(&1["name"] == "extend_license"))
    assert Enum.any?(tools, &(&1["name"] == "check_out_air_gapped_license"))
    assert Enum.any?(tools, &(&1["name"] == "request_tax_certificate_letter"))
    assert Enum.any?(tools, &(&1["name"] == "create_letter_document_upload"))
    assert Enum.any?(tools, &(&1["name"] == "finalize_letter_document_upload"))
    assert Enum.any?(tools, &(&1["name"] == "confirm_tax_certificate_delivery"))
    assert Enum.any?(tools, &(&1["name"] == "list_account_letters"))
    assert Enum.any?(tools, &(&1["name"] == "check_letter_delivery"))
  end

  test "returns a controlled tool error for scalar arguments" do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Atlas.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    conn = %{assigns: %{current_user: %User{}}}

    stub(Users, :has_scope?, fn %User{}, _scope -> true end)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "list_licenses", "arguments" => 1}
      })

    assert response["result"]["isError"]
    assert [%{"text" => "arguments must be an object."}] = response["result"]["content"]
  end
end
