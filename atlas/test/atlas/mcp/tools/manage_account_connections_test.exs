defmodule Atlas.MCP.Tools.ManageAccountConnectionsTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [insert_user!: 0]

  alias Atlas.Automations.DomainRegistry
  alias Atlas.Connections.Config
  alias Atlas.Connections.Connection
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias Atlas.Orbit.ToolPolicy

  setup do
    stub(Config, :credentials, fn _ -> %{} end)
    %{user: insert_user!()}
  end

  test "registered for MCP but never offered as an Orbit or Automation capability" do
    assert ManageAccountConnections in Server.tool_modules()
    assert "manage_account_connections" in ToolPolicy.never()
    assert Map.has_key?(DomainRegistry.exclusions(), "manage_account_connections")
  end

  test "list and disconnect require an authenticated caller" do
    for args <- [%{"action" => "list"}, %{"action" => "disconnect", "provider" => "github"}] do
      assert {:error, _} = ManageAccountConnections.execute(%{assigns: %{}}, args)
    end
  end

  test "shared Slack identities cannot discover, dispatch or directly execute personal connections", %{user: user} do
    own = insert_connection!(user)
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)

    for context <- [
          %{audit_interface: "slack"},
          %{mcp_claims: %{"slack_agent" => "systems_investigator"}},
          %{audit_interface: "mcp", mcp_claims: %{"slack_agent" => "systems_investigator"}}
        ] do
      conn = %{assigns: Map.put(context, :current_user, user)}
      response = Server.handle_message(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      names = Enum.map(response["result"]["tools"], & &1["name"])
      refute "manage_account_connections" in names
      assert "list_llm_provider_connections" in names

      for args <- [%{"action" => "list"}, %{"action" => "disconnect", "provider" => "github"}] do
        assert {:error, _} = ManageAccountConnections.execute(conn, args)

        response =
          Server.handle_message(conn, %{
            "jsonrpc" => "2.0",
            "id" => 2,
            "method" => "tools/call",
            "params" => %{"name" => "manage_account_connections", "arguments" => args}
          })

        assert response["error"]["message"] =~ "not available"
      end
    end

    assert Repo.get!(Connection, own.id)
  end

  test "metadata and disconnect are caller only and never expose credentials", %{user: user} do
    other = insert_user!()
    own = insert_connection!(user)
    foreign = insert_connection!(other)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    result = ManageAccountConnections.call(conn, %{"action" => "list"})
    assert [%{"account_name" => "octocat"} | _] = result["structuredContent"]["connections"]
    refute JSON.encode!(result) =~ "private-access"
    refute JSON.encode!(result) =~ "private-refresh"

    assert {:ok, _} = ManageAccountConnections.execute(conn, %{"action" => "disconnect", "provider" => "github"})
    assert Repo.get(Connection, own.id) == nil
    assert Repo.get!(Connection, foreign.id)
    assert {:error, _} = ManageAccountConnections.execute(conn, %{"action" => "disconnect", "provider" => "unknown"})
  end

  defp insert_connection!(user) do
    %Connection{user_id: user.id, provider: "github"}
    |> Connection.changeset(%{
      provider_user_id: "42",
      account_name: "octocat",
      access_token: "private-access",
      refresh_token: "private-refresh"
    })
    |> Repo.insert!()
  end
end
