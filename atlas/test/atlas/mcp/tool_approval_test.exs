defmodule Atlas.MCP.ToolApprovalTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Proxy.Config
  alias Atlas.MCP.Proxy.StripeCallPolicy

  setup :verify_on_exit!

  setup do
    stub(Config, :get, fn ->
      [
        servers: [
          %{
            "name" => "ovh-servers",
            "url" => "https://mcp.ovh.example/mcp",
            "auth_type" => "bearer_token",
            "bearer_token" => "token",
            "tool_allowlist" => ["get-dedicated-server-list"],
            "approval_required_tools" => ["reinstall-dedicated-server"]
          }
        ]
      ]
    end)

    stub(Req, :post, &upstream/1)
    :ok
  end

  @reinstall %{
    "serviceName" => "ns1.example",
    "operatingSystem" => "ubuntu2404-server_64",
    "customizations" => %{"hostname" => "fleet", "sshKey" => "ssh-ed25519 AAAA fleet"}
  }

  test "a gated call waits for its owner's approval, then runs exactly once" do
    owner = insert_user!()
    conn = agent_conn(owner)

    assert [%{"name" => "ovh-servers__reinstall-dedicated-server", "description" => description}, _] =
             conn
             |> Proxy.list_hoisted_tools()
             |> Enum.sort_by(&(&1["name"] != "ovh-servers__reinstall-dedicated-server"))

    assert description =~ "approval"

    assert {:error, message} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", @reinstall)
    assert [%{id: id}] = MCP.list_pending_tool_approvals(owner)
    assert message =~ "/admin/mcps#mcp-approval-#{id}"
    refute_received {:tools_call, _}

    # Asking again before anyone decides reuses the open request.
    assert {:error, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", @reinstall)
    assert [%{id: ^id}] = MCP.list_pending_tool_approvals(owner)

    # Nobody else can answer it, including another Atlas user.
    assert {:error, :not_found} = MCP.decide_tool_approval(insert_user!(), id, "approved")
    assert {:ok, _} = MCP.decide_tool_approval(owner, id, "approved")

    # Different arguments are a different call.
    other = put_in(@reinstall, ["customizations", "hostname"], "other")
    assert {:error, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", other)
    refute_received {:tools_call, _}

    # Key order is not part of the call.
    reordered = @reinstall |> Enum.reverse() |> Map.new()
    assert {:ok, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", reordered)
    assert_received {:tools_call, %{"name" => "reinstall-dedicated-server", "arguments" => ^reordered}}

    # The approval is spent.
    assert {:error, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", @reinstall)
    refute_received {:tools_call, _}
  end

  test "a rejected request never runs" do
    owner = insert_user!()
    conn = agent_conn(owner)

    assert {:error, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", @reinstall)
    [%{id: id}] = MCP.list_pending_tool_approvals(owner)
    assert {:ok, _} = MCP.decide_tool_approval(owner, id, "rejected")
    assert {:error, :not_found} = MCP.decide_tool_approval(owner, id, "approved")

    assert {:error, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", @reinstall)
    refute_received {:tools_call, _}
  end

  test "callers that act as a fixed operator cannot reach a gated tool" do
    user = insert_user!()
    conn = %{assigns: %{current_user: user, audit_interface: "slack"}}

    assert {:error, message} = Proxy.call_hoisted_tool(conn, "ovh-servers__reinstall-dedicated-server", @reinstall)
    assert message =~ "only callable over Atlas MCP"
    assert MCP.list_pending_tool_approvals(user) == []
    refute_received {:tools_call, _}
  end

  test "ungated tools on the same server run without approval" do
    conn = agent_conn(insert_user!())

    assert {:ok, _} = Proxy.call_hoisted_tool(conn, "ovh-servers__get-dedicated-server-list", %{})
    assert_received {:tools_call, %{"name" => "get-dedicated-server-list"}}
  end

  describe "stripe" do
    setup do
      stub(Config, :get, fn ->
        [
          servers: [
            %{
              "name" => "stripe",
              "url" => "https://mcp.stripe.example/mcp",
              "auth_type" => "bearer_token",
              "bearer_token" => "token",
              "allowed_user_emails" => ["Billing@Tuist.dev"],
              "tool_allowlist" => ["stripe_api_read", "stripe_api_write"],
              "call_policy" => StripeCallPolicy
            }
          ]
        ]
      end)

      %{owner: insert_user!(%{email: "billing@tuist.dev"})}
    end

    @create_price %{
      "stripe_api_operation_id" => "PostPrices",
      "stripe_context" => "acct_1",
      "parameters" => %{"lookup_key" => "runner_cache_volume", "currency" => "usd"}
    }

    test "only the named people see the server, and only over their own MCP connection", %{owner: owner} do
      assert [_ | _] = Proxy.list_hoisted_tools(agent_conn(owner))
      assert Proxy.list_hoisted_tools(agent_conn(insert_user!())) == []
      assert Proxy.list_hoisted_tools(%{assigns: %{current_user: owner, audit_interface: "slack"}}) == []

      assert {:error, _} = Proxy.call_hoisted_tool(agent_conn(insert_user!()), "stripe__stripe_api_read", %{})
      refute_received {:tools_call, _}

      assert [%{server: %{name: "stripe"}}] = MCP.list_servers(owner)
      assert MCP.list_servers(insert_user!()) == []
    end

    test "reads and test-mode writes run without approval", %{owner: owner} do
      conn = agent_conn(owner)

      assert {:ok, _} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_read", %{"livemode" => true})
      assert_received {:tools_call, %{"name" => "stripe_api_read"}}

      test_mode = Map.put(@create_price, "livemode", false)
      assert {:ok, _} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_write", test_mode)
      assert_received {:tools_call, %{"name" => "stripe_api_write", "arguments" => ^test_mode}}
      assert MCP.list_pending_tool_approvals(owner) == []
    end

    test "a live-mode write waits for the caller's approval of that exact call", %{owner: owner} do
      conn = agent_conn(owner)
      live = Map.put(@create_price, "livemode", true)

      assert {:error, message} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_write", live)
      assert [%{id: id}] = MCP.list_pending_tool_approvals(owner)
      assert message =~ "/admin/mcps#mcp-approval-#{id}"
      refute_received {:tools_call, _}

      assert {:ok, _} = MCP.decide_tool_approval(owner, id, "approved")

      changed = put_in(live, ["parameters", "currency"], "eur")
      assert {:error, _} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_write", changed)
      refute_received {:tools_call, _}

      assert {:ok, _} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_write", live)
      assert_received {:tools_call, %{"name" => "stripe_api_write", "arguments" => ^live}}
    end

    test "a write that does not say it is test mode counts as live", %{owner: owner} do
      conn = agent_conn(owner)

      for livemode <- [nil, "false"] do
        args = if livemode, do: Map.put(@create_price, "livemode", livemode), else: @create_price
        assert {:error, message} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_write", args)
        assert message =~ "approval"
      end

      refute_received {:tools_call, _}
    end

    test "meter events are refused in either mode", %{owner: owner} do
      conn = agent_conn(owner)

      for op <- ["PostBillingMeterEvents", "PostV2BillingMeterEventStream"], livemode <- [true, false] do
        args = %{"stripe_api_operation_id" => op, "stripe_context" => "acct_1", "livemode" => livemode}
        assert {:error, message} = Proxy.call_hoisted_tool(conn, "stripe__stripe_api_write", args)
        assert message =~ "double-bill"
      end

      assert MCP.list_pending_tool_approvals(owner) == []
      refute_received {:tools_call, _}
    end

    test "tools outside the allowlist are unreachable", %{owner: owner} do
      assert {:error, _} = Proxy.call_hoisted_tool(agent_conn(owner), "stripe__stripe_analytics", %{})
      refute_received {:tools_call, _}
    end
  end

  defp agent_conn(user), do: %{assigns: %{current_user: user, audit_interface: "mcp"}}

  defp upstream(%Req.Request{} = request) do
    json = request.options.json

    case json["method"] do
      "initialize" ->
        {:ok,
         %Req.Response{
           status: 200,
           headers: %{"mcp-session-id" => ["session-1"]},
           body: %{"jsonrpc" => "2.0", "id" => json["id"], "result" => %{"protocolVersion" => "2025-03-26"}}
         }}

      "notifications/initialized" ->
        {:ok, %Req.Response{status: 202, body: ""}}

      "tools/list" ->
        tools =
          Enum.map(
            [
              "get-dedicated-server-list",
              "reinstall-dedicated-server",
              "terminate-dedicated-server",
              "stripe_api_read",
              "stripe_api_write",
              "stripe_analytics"
            ],
            &%{"name" => &1, "inputSchema" => %{"type" => "object"}}
          )

        {:ok,
         %Req.Response{status: 200, body: %{"jsonrpc" => "2.0", "id" => json["id"], "result" => %{"tools" => tools}}}}

      "tools/call" ->
        send(self(), {:tools_call, json["params"]})

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "jsonrpc" => "2.0",
             "id" => json["id"],
             "result" => %{"content" => [%{"type" => "text", "text" => "ok"}]}
           }
         }}
    end
  end
end
