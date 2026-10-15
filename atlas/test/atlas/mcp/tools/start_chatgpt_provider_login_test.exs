defmodule Atlas.MCP.Tools.StartChatGPTProviderLoginTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connection
  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.StartChatGPTProviderLogin

  test "returns only user-facing instructions and an owner-scoped login handle" do
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    user = insert_user!()
    conn = mcp_conn(user)
    assert {:ok, login} = execute_tool(StartChatGPTProviderLogin, conn, %{})
    assert login.user_code == "USER-CODE"
    assert login.verification_url == "https://auth.openai.com/codex/device"
    assert login.interval == 5
    assert DateTime.after?(login.expires_at, DateTime.utc_now())
    refute inspect(login) =~ "private-device-id"
    assert {:error, _} = execute_tool(StartChatGPTProviderLogin, conn, %{})
    assert {:error, :not_found} = Connections.poll_chatgpt(insert_user!(), login.login_id)
    assert Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt").pending_login
  end

  test "requires authentication and explains unavailable sign-in without raw provider errors" do
    assert {:error, message} = execute_tool(StartChatGPTProviderLogin, %{assigns: %{}}, %{})
    assert message =~ "authenticated"
    conn = insert_user!() |> mcp_conn()
    stub(ChatGPT, :start, fn -> {:error, :chatgpt_not_configured} end)
    assert {:error, message} = execute_tool(StartChatGPTProviderLogin, conn, %{})
    assert message =~ "administrator"
    stub(ChatGPT, :start, fn -> {:error, {:upstream, "private-provider-response"}} end)
    assert {:error, message} = execute_tool(StartChatGPTProviderLogin, conn, %{})
    refute message =~ "private-provider-response"
  end

  test "tool audits omit inputs and never retain returned codes or private provider data" do
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    conn = insert_user!() |> mcp_conn()

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "start_chatgpt_provider_login", "arguments" => %{"unexpected" => "private-input"}}
      })

    refute response["result"]["isError"]
    assert response["result"]["structuredContent"]["user_code"] == "USER-CODE"
    refute inspect(response) =~ "private-device-id"
    assert Repo.get_by!(Activity, action: "mcp.tool_called").metadata["arguments"] == %{}
    audit = inspect(Repo.all(Activity))
    refute audit =~ "private-input"
    refute audit =~ "USER-CODE"
    refute audit =~ "private-device-id"
  end

  defp device_login do
    %{
      "device_auth_id" => "private-device-id",
      "user_code" => "USER-CODE",
      "client_id" => "atlas-client",
      "interval" => 5,
      "verification_url" => "https://auth.openai.com/codex/device"
    }
  end
end
