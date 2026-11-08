defmodule AtlasWeb.BusinessProfileControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [execute_tool: 3, mcp_conn: 1]

  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.GetMyBusinessProfile
  alias Atlas.MCP.Tools.UpdateMyBusinessProfile

  test "API and MCP edit only the caller's opt-in shared profile, independently of private description", %{conn: conn} do
    {_, user} = log_in_user(conn, %{scopes: []})
    {:ok, _} = Atlas.Users.update_my_profile(user, "Private preferences")
    token = oauth_access_token_fixture(user)

    profile = %{
      "enabled" => true,
      "role" => "customer success",
      "expertise" => ["caching"],
      "responsibilities" => ["account:#{Ecto.UUID.generate()}"]
    }

    assert build_conn() |> get("/api/me/business-profile") |> json_response(401)

    response =
      build_conn() |> put_req_header("authorization", "Bearer #{token}") |> put("/api/me/business-profile", profile)

    assert json_response(response, 200) == %{"business_profile" => profile}
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert {:ok, ^profile} = execute_tool(GetMyBusinessProfile, mcp_conn(user), %{})

    assert {:error, _} =
             execute_tool(UpdateMyBusinessProfile, mcp_conn(user), Map.put(profile, "user_id", Ecto.UUID.generate()))

    assert {:error, _} =
             execute_tool(UpdateMyBusinessProfile, mcp_conn(user), Map.put(profile, "role", "invalid\0role"))

    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)

    for slack <- [
          %{assigns: %{current_user: user, audit_interface: "slack"}},
          %{assigns: %{current_user: user, mcp_claims: %{"slack_agent" => true}}}
        ] do
      assert {:error, _} = execute_tool(UpdateMyBusinessProfile, slack, Map.put(profile, "enabled", false))
      assert {:error, _} = execute_tool(GetMyBusinessProfile, slack, %{})
      response = Server.handle_message(slack, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      names = Enum.map(response["result"]["tools"], & &1["name"])
      refute "get_my_business_profile" in names
      refute "update_my_business_profile" in names
    end

    assert {:ok, ^profile} = execute_tool(GetMyBusinessProfile, mcp_conn(user), %{})
    assert {:ok, disabled} = execute_tool(UpdateMyBusinessProfile, mcp_conn(user), Map.put(profile, "enabled", false))
    assert disabled["enabled"] == false
    assert Atlas.Users.get_user(user.id).description == "Private preferences"
  end
end
