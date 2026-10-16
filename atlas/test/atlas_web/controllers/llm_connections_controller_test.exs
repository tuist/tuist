defmodule AtlasWeb.LLMConnectionsControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connections

  test "personal provider endpoints require authentication", %{conn: conn} do
    for {method, path} <- [
          {:get, ~p"/api/me/llm-providers"},
          {:put, ~p"/api/me/llm-providers/claude"},
          {:post, ~p"/api/me/llm-providers/chatgpt/login"},
          {:post, ~p"/api/me/llm-providers/chatgpt/login/poll"},
          {:delete, ~p"/api/me/llm-providers/claude"}
        ] do
      assert conn |> dispatch(@endpoint, method, path, %{}) |> json_response(401) == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end
  end

  test "current-user API saves, replaces and disconnects Claude without leaking secrets or accepting owner IDs", %{
    conn: conn
  } do
    {_conn, user} = log_in_user(conn)
    {_conn, other} = log_in_user(build_conn())
    api = api_conn(user)
    token = "sk-ant-oat01-" <> String.duplicate("a", 64)

    saved = put(api, ~p"/api/me/llm-providers/claude", %{token: token, user_id: other.id, provider: "chatgpt"})
    assert %{"provider" => "claude", "credential_configured" => true} = json_response(saved, 200)
    refute saved.resp_body =~ token
    assert get_resp_header(saved, "cache-control") == ["no-store"]
    assert {:ok, %{access_token: ^token}} = Connections.credentials(user, "claude")
    assert {:error, :not_connected} = Connections.credentials(other, "claude")

    listing = get(api, ~p"/api/me/llm-providers")

    assert %{"providers" => [%{"provider" => "claude", "credential_configured" => true}, %{"provider" => "chatgpt"}]} =
             json_response(listing, 200)

    refute listing.resp_body =~ "access_token"
    refute listing.resp_body =~ "refresh_token"
    assert %{"credential_configured" => false} = api |> delete(~p"/api/me/llm-providers/claude") |> json_response(200)
  end

  test "invalid credentials return a bounded error without echoing the token", %{conn: conn} do
    {_conn, user} = log_in_user(conn)
    response = put(api_conn(user), ~p"/api/me/llm-providers/claude", %{token: "private-invalid-secret"})
    assert %{"error" => "invalid_claude_token"} = json_response(response, 422)
    refute response.resp_body =~ "private-invalid-secret"
  end

  test "ChatGPT sign-in fails clearly when no OAuth client is configured", %{conn: conn} do
    {_conn, user} = log_in_user(conn)
    stub(ChatGPT, :client_id, fn -> {:error, :chatgpt_not_configured} end)

    assert %{"error" => "chatgpt_not_configured"} =
             api_conn(user) |> post(~p"/api/me/llm-providers/chatgpt/login") |> json_response(503)
  end

  defp api_conn(user), do: build_conn() |> put_req_header("authorization", "Bearer #{oauth_access_token_fixture(user)}")
end
