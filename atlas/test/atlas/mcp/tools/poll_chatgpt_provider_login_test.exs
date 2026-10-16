defmodule Atlas.MCP.Tools.PollChatGPTProviderLoginTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connection
  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.PollChatGPTProviderLogin

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
    {:ok, login} = Connections.start_chatgpt(user)
    %{user: user, conn: mcp_conn(user), login: login}
  end

  test "polling enforces the interval and saves credentials without returning them", %{
    user: user,
    conn: conn,
    login: login
  } do
    expect(ChatGPT, :poll, fn _pending ->
      {:ok,
       %{
         access_token: "private-access-token",
         refresh_token: "private-refresh-token",
         expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
       }}
    end)

    assert {:ok, %{status: "pending"}} = execute_tool(PollChatGPTProviderLogin, conn, %{"login_id" => login.login_id})
    allow_poll(user)
    assert {:ok, %{status: "connected"}} = execute_tool(PollChatGPTProviderLogin, conn, %{"login_id" => login.login_id})
    assert {:ok, %{access_token: "private-access-token"}} = Connections.credentials(user, "chatgpt")
    assert Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt").pending_login == nil
  end

  test "requires authentication and never lets another user complete the login", %{user: user, login: login} do
    assert {:error, message} = execute_tool(PollChatGPTProviderLogin, %{assigns: %{}}, %{"login_id" => login.login_id})
    assert message =~ "authenticated"
    other_conn = insert_user!() |> mcp_conn()

    assert {:error, _} =
             execute_tool(PollChatGPTProviderLogin, other_conn, %{"login_id" => login.login_id, "user_id" => user.id})

    assert {:error, :not_connected} = Connections.credentials(user, "chatgpt")
  end

  test "reports sanitized transient errors while preserving the pending login", %{user: user, conn: conn, login: login} do
    stub(ChatGPT, :poll, fn _pending -> {:error, :provider_unavailable} end)
    allow_poll(user)
    assert {:error, message} = execute_tool(PollChatGPTProviderLogin, conn, %{"login_id" => login.login_id})
    assert message =~ "retry this login"
    assert Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt").pending_login
    assert {:error, _} = execute_tool(PollChatGPTProviderLogin, conn, %{})
  end

  test "poll calls do not audit login handles", %{user: user, conn: conn, login: login} do
    expect(ChatGPT, :poll, fn _pending -> {:error, :authorization_pending} end)
    allow_poll(user)

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "poll_chatgpt_provider_login", "arguments" => %{"login_id" => login.login_id}}
      })

    assert response["result"]["structuredContent"] == %{"status" => "pending"}
    refute inspect(Repo.all(Activity)) =~ login.login_id
    assert Repo.get_by!(Activity, action: "mcp.tool_called").metadata["arguments"] == %{}
  end

  defp allow_poll(user) do
    Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt")
    |> Ecto.Changeset.change(next_poll_at: DateTime.add(DateTime.utc_now(:second), -1))
    |> Repo.update!()
  end
end
