defmodule Atlas.MCP.ToolApprovalTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Proxy.Config

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
            ["get-dedicated-server-list", "reinstall-dedicated-server", "terminate-dedicated-server"],
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
