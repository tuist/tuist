defmodule Atlas.MCP.Tools.SetOVHServerDisplayNameTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.MCP
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.Proxy.Config
  alias Atlas.MCP.Tools.SetOVHServerDisplayName

  setup :verify_on_exit!

  setup do
    stub(Config, :get, fn ->
      [
        servers: [
          %{
            "name" => "ovh-services",
            "url" => "https://mcp.ovh.example/mcp/v1_services",
            "auth_type" => "oauth2",
            "authorization_url" => "https://mcp.ovh.example/oauth-proxy/authorization",
            "token_url" => "https://mcp.ovh.example/oauth-proxy/token"
          }
        ]
      ]
    end)

    :ok
  end

  @rename %{"serviceName" => "ns1.ip-1-2-3.us", "displayName" => "tuist-kura-ovh-production-us-east"}

  test "renames with the caller's own OVH session only after they approve that exact call" do
    owner = insert_user!()
    connect!(insert_user!(), "other-token")
    connect!(owner, "owner-token")
    ovh("unnamed", "owner-token")
    conn = agent_conn(owner)

    assert {:error, message} = SetOVHServerDisplayName.execute(conn, @rename)
    assert [%{id: id, server_name: "ovh-services"}] = MCP.list_pending_tool_approvals(owner)
    assert message =~ "/approvals/#{id}"
    refute_received {:put, _}

    assert {:ok, _} = MCP.decide_tool_approval(owner, id, "approved")

    assert {:ok, %{previousDisplayName: "unnamed", changed: true, serviceId: 42}} =
             SetOVHServerDisplayName.execute(conn, @rename)

    assert_received {:put, %{"resource" => %{"displayName" => "tuist-kura-ovh-production-us-east"}}}

    # The approval is spent; renaming again to another name needs a new one.
    assert {:error, _} = SetOVHServerDisplayName.execute(conn, %{@rename | "displayName" => "other"})
    refute_received {:put, _}
  end

  test "a server that already has the name is left alone without an approval" do
    owner = insert_user!()
    connect!(owner, "owner-token")
    ovh(@rename["displayName"], "owner-token")

    assert {:ok, %{changed: false}} = SetOVHServerDisplayName.execute(agent_conn(owner), @rename)
    assert MCP.list_pending_tool_approvals(owner) == []
    refute_received {:put, _}
  end

  test "a rename OVH silently drops is reported, not claimed" do
    owner = insert_user!()
    connect!(owner, "owner-token")
    ovh("unnamed", "owner-token", apply_put: false)
    approve_next!(owner)

    assert {:error, message} = SetOVHServerDisplayName.execute(agent_conn(owner), @rename)
    assert message =~ "still \"unnamed\""
    assert_received {:put, _}
  end

  test "a session OVH's REST API refuses points at the human rename path" do
    owner = insert_user!()
    connect!(owner, "owner-token")
    stub_http(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {:error, message} = SetOVHServerDisplayName.execute(agent_conn(owner), @rename)
    assert message =~ "HTTP 401"
    assert message =~ "baremetal:mark-ovh"
  end

  test "callers that act as a fixed operator cannot rename" do
    user = insert_user!()
    connect!(user, "owner-token")
    ovh("unnamed", "owner-token")

    assert {:error, message} =
             SetOVHServerDisplayName.execute(%{assigns: %{current_user: user, audit_interface: "slack"}}, @rename)

    assert message =~ "only callable over Atlas MCP"
    assert MCP.list_pending_tool_approvals(user) == []
    refute_received {:put, _}
  end

  defp agent_conn(user), do: %{assigns: %{current_user: user, audit_interface: "mcp"}}

  defp approve_next!(owner) do
    assert {:error, _} = SetOVHServerDisplayName.execute(agent_conn(owner), @rename)
    [%{id: id}] = MCP.list_pending_tool_approvals(owner)
    {:ok, _} = MCP.decide_tool_approval(owner, id, "approved")
  end

  defp connect!(user, token) do
    %OAuthSession{user_id: user.id, server_name: "ovh-services"}
    |> OAuthSession.changeset(%{
      access_token: token,
      expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  # A fake of the three OVH endpoints the rename touches, holding the service's
  # displayName in the test process.
  defp ovh(display_name, token, opts \\ []) do
    Process.put(:display_name, display_name)

    stub_http(fn conn ->
      assert ["Bearer #{token}"] == Plug.Conn.get_req_header(conn, "authorization")

      case {conn.method, conn.request_path} do
        {"GET", "/1.0/dedicated/server/ns1.ip-1-2-3.us/serviceInfos"} ->
          Req.Test.json(conn, %{"serviceId" => 42})

        {"GET", "/1.0/services/42"} ->
          Req.Test.json(conn, %{"resource" => %{"displayName" => Process.get(:display_name)}})

        # The legacy endpoint keeps serving the name from before any rename.
        {"GET", "/1.0/service/42"} ->
          Req.Test.json(conn, %{"resource" => %{"displayName" => display_name}})

        {"PUT", "/1.0/service/42"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(body)
          send(self(), {:put, body})
          if Keyword.get(opts, :apply_put, true), do: Process.put(:display_name, body["resource"]["displayName"])
          Req.Test.json(conn, nil)
      end
    end)
  end

  defp stub_http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
