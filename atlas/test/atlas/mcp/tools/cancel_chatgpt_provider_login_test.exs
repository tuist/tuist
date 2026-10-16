defmodule Atlas.MCP.Tools.CancelChatGPTProviderLoginTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connection
  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.CancelChatGPTProviderLogin

  setup do
    stub(ChatGPT, :start, fn ->
      {:ok,
       %{
         "device_auth_id" => "private-device-id",
         "user_code" => "USER-CODE",
         "client_id" => "atlas-client",
         "interval" => 5,
         "verification_url" => "https://auth.openai.com/codex/device"
       }}
    end)

    user = insert_user!()

    %Connection{user_id: user.id, provider: "chatgpt"}
    |> Connection.changeset(%{
      access_token: "old-access-token",
      refresh_token: "old-refresh-token",
      expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
    })
    |> Repo.insert!()

    {:ok, login} = Connections.start_chatgpt(user)
    %{user: user, conn: mcp_conn(user), login: login}
  end

  test "cancels pending login while preserving the saved connection", %{user: user, conn: conn, login: login} do
    assert {:ok, %{status: "cancelled"}} =
             execute_tool(CancelChatGPTProviderLogin, conn, %{"login_id" => login.login_id})

    assert {:error, :not_found} = Connections.poll_chatgpt(user, login.login_id)
    assert {:ok, %{access_token: "old-access-token"}} = Connections.credentials(user, "chatgpt")
    assert {:error, _} = execute_tool(CancelChatGPTProviderLogin, conn, %{"login_id" => login.login_id})
  end

  test "requires authentication and cannot cancel another user's login", %{user: user, login: login} do
    assert {:error, message} =
             execute_tool(CancelChatGPTProviderLogin, %{assigns: %{}}, %{"login_id" => login.login_id})

    assert message =~ "authenticated"
    other_conn = insert_user!() |> mcp_conn()

    assert {:error, _} =
             execute_tool(CancelChatGPTProviderLogin, other_conn, %{"login_id" => login.login_id, "user_id" => user.id})

    assert {:ok, %{status: "pending"}} = Connections.poll_chatgpt(user, login.login_id)
    assert {:error, _} = execute_tool(CancelChatGPTProviderLogin, other_conn, %{})
  end

  test "successful and failed cancellations never persist the login handle in audits", %{conn: conn, login: login} do
    for _attempt <- 1..2 do
      response =
        Server.handle_message(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "cancel_chatgpt_provider_login", "arguments" => %{"login_id" => login.login_id}}
        })

      refute inspect(response) =~ login.login_id
    end

    activities = Repo.all(Activity)
    refute inspect(activities) =~ login.login_id
    calls = Enum.filter(activities, &(&1.action == "mcp.tool_called"))
    assert length(calls) == 2
    assert Enum.all?(calls, &(&1.metadata["arguments"] == %{}))
  end
end
