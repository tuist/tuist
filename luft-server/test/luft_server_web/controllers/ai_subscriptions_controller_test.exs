defmodule LuftServerWeb.AISubscriptionsControllerTest do
  use LuftServerWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias LuftServer.AISubscriptions.Subscription
  alias LuftServer.NativeAuth
  alias LuftServer.Repo
  alias LuftServerWeb.ConversationsSocket

  @endpoint LuftServerWeb.Endpoint

  setup do
    Req.Test.set_req_test_to_shared()
    pid = self()

    # OpenAI's device authorization, approving at once.
    Req.Test.stub(LuftServer.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(pid, {:openai, conn.request_path, body})

      case conn.request_path do
        "/api/accounts/deviceauth/usercode" ->
          Req.Test.json(conn, %{device_auth_id: "device-1", user_code: "ABCD-EFGH", interval: 5})

        "/api/accounts/deviceauth/token" ->
          Req.Test.json(conn, %{authorization_code: "code", code_verifier: "verifier"})

        "/oauth/token" ->
          Req.Test.json(conn, %{
            access_token: LuftServer.FakeOpenAI.token(),
            refresh_token: "refresh",
            expires_in: 3600
          })
      end
    end)

    %{bearer: bearer()}
  end

  test "changes made through Luft are saved and reach the person's open channels at once", %{
    bearer: bearer
  } do
    {:ok, socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})

    assert {:ok, %{subscriptions: [%{"connected" => false}, %{"connected" => false}]}, _joined} =
             subscribe_and_join(socket, "ai_subscriptions")

    conn = authorized(bearer)

    assert %{"message" => _} =
             conn
             |> put("/api/me/ai-subscriptions/claude", %{token: "nope"})
             |> json_response(422)

    refute_push "snapshot", _

    token = "sk-ant-oat01-" <> String.duplicate("a", 40)

    assert %{"subscriptions" => subscriptions} =
             conn
             |> put("/api/me/ai-subscriptions/claude", %{token: token})
             |> json_response(200)

    # Luft says which subscriptions can run its threads: Claude's can't.
    assert %{"connected" => true, "runs_threads" => false} = provider(subscriptions, "claude")
    assert_push "snapshot", %{subscriptions: pushed}
    assert provider(pushed, "claude")["connected"]
    # Saved encrypted, never as the token itself.
    refute raw_columns_contain?(token)

    assert %{"login_id" => login_id, "user_code" => "ABCD-EFGH"} =
             authorized(bearer)
             |> post("/api/me/ai-subscriptions/chatgpt/login")
             |> json_response(200)

    assert_received {:openai, "/api/accounts/deviceauth/usercode", body}
    assert Jason.decode!(body) == %{"client_id" => "test-chatgpt-client"}

    # OpenAI's polling interval holds back the first poll.
    assert %{"status" => "pending"} = poll(bearer, login_id)
    refute_received {:openai, "/api/accounts/deviceauth/token", _}

    Repo.update_all(Subscription,
      set: [next_poll_at: DateTime.add(DateTime.utc_now(:second), -1)]
    )

    assert %{"status" => "connected"} = poll(bearer, login_id)
    assert_push "snapshot", %{subscriptions: pushed}
    assert %{"connected" => true, "runs_threads" => true} = provider(pushed, "chatgpt")

    # The sign-in finished, so there is nothing left to cancel.
    assert authorized(bearer)
           |> delete("/api/me/ai-subscriptions/chatgpt/login?login_id=#{login_id}")
           |> json_response(404)

    assert %{"subscriptions" => _} =
             authorized(bearer) |> delete("/api/me/ai-subscriptions/claude") |> json_response(200)

    assert_push "snapshot", %{subscriptions: pushed}
    refute provider(pushed, "claude")["connected"]
    assert provider(pushed, "chatgpt")["connected"]

    assert authorized(bearer) |> delete("/api/me/ai-subscriptions/other") |> json_response(404)
  end

  test "a cancelled ChatGPT sign-in can no longer connect", %{bearer: bearer} do
    assert %{"login_id" => login_id} =
             authorized(bearer)
             |> post("/api/me/ai-subscriptions/chatgpt/login")
             |> json_response(200)

    assert authorized(bearer)
           |> delete("/api/me/ai-subscriptions/chatgpt/login?login_id=#{login_id}")
           |> response(204)

    assert authorized(bearer)
           |> post("/api/me/ai-subscriptions/chatgpt/login/poll", %{login_id: login_id})
           |> json_response(404)

    assert %{"subscriptions" => subscriptions} =
             authorized(bearer) |> get("/api/me/ai-subscriptions") |> json_response(200)

    refute provider(subscriptions, "chatgpt")["connected"]
  end

  test "ChatGPT sign-ins are limited per person", %{bearer: bearer} do
    for _attempt <- 1..5 do
      authorized(bearer) |> post("/api/me/ai-subscriptions/chatgpt/login") |> json_response(200)
    end

    assert authorized(bearer)
           |> post("/api/me/ai-subscriptions/chatgpt/login")
           |> json_response(429)
  end

  defp poll(bearer, login_id) do
    authorized(bearer)
    |> post("/api/me/ai-subscriptions/chatgpt/login/poll", %{login_id: login_id})
    |> json_response(200)
  end

  defp raw_columns_contain?(value) do
    %{rows: rows} =
      Repo.query!("SELECT access_token, refresh_token FROM ai_subscriptions")

    rows |> List.flatten() |> Enum.any?(&(is_binary(&1) and String.contains?(&1, value)))
  end

  defp provider(subscriptions, name), do: Enum.find(subscriptions, &(&1["provider"] == name))

  defp authorized(bearer) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> bearer)
    |> put_req_header("accept", "application/json")
  end

  defp bearer do
    verifier = String.duplicate("v", 43)

    request = %{
      "client_id" => NativeAuth.client_id(),
      "response_type" => "code",
      "redirect_uri" => "luft://oauth-callback",
      "state" => "state",
      "code_challenge_method" => "S256",
      "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    }

    {:ok, callback, _session} =
      NativeAuth.complete(
        %{
          claims: %{"sub" => "1", "preferred_username" => "one"},
          tokens: %{
            "access_token" => "upstream-secret",
            "refresh_token" => "refresh",
            "expires_in" => 3600
          }
        },
        request
      )

    params = callback |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    {:ok, credentials} =
      NativeAuth.exchange(%{
        "grant_type" => "authorization_code",
        "client_id" => NativeAuth.client_id(),
        "redirect_uri" => "luft://oauth-callback",
        "code" => params["code"],
        "code_verifier" => verifier
      })

    credentials.access_token
  end
end
