defmodule Atlas.MCP.Tools.ConnectClaudeProviderTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Audit.Activity
  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.ConnectClaudeProvider

  test "creates and replaces only the caller's credentials, returning no tokens" do
    user = insert_user!()
    other = insert_user!()
    conn = mcp_conn(user)

    for token <- [token("a"), token("b")] do
      assert {:ok, %{provider: "claude", credential_configured: true}} =
               execute_tool(ConnectClaudeProvider, conn, %{"token" => token, "user_id" => other.id})

      assert {:ok, %{access_token: ^token}} = Connections.credentials(user, "claude")
      assert {:error, :not_connected} = Connections.credentials(other, "claude")
    end
  end

  test "requires authentication and rejects missing or malformed tokens without echoing them" do
    assert {:error, message} = execute_tool(ConnectClaudeProvider, %{assigns: %{}}, %{"token" => token("a")})
    assert message =~ "authenticated"
    conn = insert_user!() |> mcp_conn()

    for args <- [%{}, %{"token" => "private-invalid-token"}, %{"token" => nil}] do
      assert {:error, message} = execute_tool(ConnectClaudeProvider, conn, args)
      refute message =~ "private-invalid-token"
    end
  end

  test "successful and failed tool-call audits omit the entire input payload" do
    user = insert_user!()
    conn = mcp_conn(user)

    for token <- [token("a"), "private-invalid-token"] do
      response = call(conn, %{"token" => token, "unexpected" => %{"secret" => token}})
      refute inspect(response) =~ token
    end

    response = call(conn, "private-malformed-input")
    assert response["result"]["isError"]
    refute inspect(response) =~ "private-malformed-input"

    activities = Repo.all(Activity)
    refute inspect(activities) =~ token("a")
    refute inspect(activities) =~ "private-invalid-token"
    refute inspect(activities) =~ "private-malformed-input"
    calls = Enum.filter(activities, &(&1.action == "mcp.tool_called"))
    assert length(calls) == 3
    assert Enum.all?(calls, &(&1.metadata["arguments"] == %{}))
    assert Enum.sort(Enum.map(calls, & &1.metadata["status"])) == ["error", "error", "ok"]

    assert Enum.any?(
             activities,
             &(&1.action == "llm_provider.connected" and &1.interface == "mcp" and &1.actor_id == user.id)
           )
  end

  defp call(conn, args) do
    Server.handle_message(conn, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "connect_claude_provider", "arguments" => args}
    })
  end

  defp token(char), do: "sk-ant-oat01-" <> String.duplicate(char, 64)
end
