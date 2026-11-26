defmodule LuftServerWeb.AISubscriptionsControllerTest do
  use LuftServerWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias LuftServer.NativeAuth
  alias LuftServerWeb.ConversationsSocket

  @endpoint LuftServerWeb.Endpoint

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, state} = Agent.start_link(fn -> %{claude: false, chatgpt: false} end)
    pid = self()

    # Tuist's `/api/me/ai-subscriptions`, holding what each provider has saved.
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert get_req_header(conn, "authorization") == ["Bearer upstream-secret"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(pid, {:tuist, conn.method, conn.request_path, conn.query_string, body})

      case {conn.method, conn.request_path} do
        {"PUT", "/api/me/ai-subscriptions/claude"} ->
          if Jason.decode!(body)["token"] == "sk-ant-oat01-valid" do
            Agent.update(state, &%{&1 | claude: true})
            Req.Test.json(conn, list(state))
          else
            conn |> put_status(422) |> Req.Test.json(%{message: "Invalid token."})
          end

        {"POST", "/api/me/ai-subscriptions/chatgpt/login"} ->
          Req.Test.json(conn, %{
            login_id: "login-1",
            user_code: "ABCD-EFGH",
            verification_url: "https://auth.openai.com/codex/device",
            interval: 5,
            expires_at: "2026-11-25T23:00:00Z"
          })

        {"POST", "/api/me/ai-subscriptions/chatgpt/login/poll"} ->
          Agent.update(state, &%{&1 | chatgpt: true})
          Req.Test.json(conn, %{status: "connected"})

        {"DELETE", "/api/me/ai-subscriptions/chatgpt/login"} ->
          Plug.Conn.send_resp(conn, 204, "")

        {"DELETE", "/api/me/ai-subscriptions/" <> provider} ->
          Agent.update(state, &Map.put(&1, String.to_existing_atom(provider), false))
          Req.Test.json(conn, list(state))

        {"GET", "/api/me/ai-subscriptions"} ->
          Req.Test.json(conn, list(state))
      end
    end)

    bearer = bearer()
    %{bearer: bearer, state: state}
  end

  test "changes made through Luft reach the person's open channels at once", %{bearer: bearer} do
    {:ok, socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})

    assert {:ok, %{subscriptions: [%{"connected" => false}, %{"connected" => false}]}, _joined} =
             subscribe_and_join(socket, "ai_subscriptions")

    conn = authorized(bearer)

    assert %{"message" => "Invalid token."} =
             conn
             |> put("/api/me/ai-subscriptions/claude", %{token: "nope"})
             |> json_response(422)

    refute_push "snapshot", _

    assert %{"subscriptions" => subscriptions} =
             conn
             |> put("/api/me/ai-subscriptions/claude", %{token: "sk-ant-oat01-valid"})
             |> json_response(200)

    # Luft says which subscriptions can run its threads: Claude's can't.
    assert %{"connected" => true, "runs_threads" => false} = provider(subscriptions, "claude")
    assert_push "snapshot", %{subscriptions: pushed}
    assert provider(pushed, "claude")["connected"]

    assert %{"login_id" => "login-1", "user_code" => "ABCD-EFGH"} =
             authorized(bearer)
             |> post("/api/me/ai-subscriptions/chatgpt/login")
             |> json_response(200)

    assert %{"status" => "connected"} =
             authorized(bearer)
             |> post("/api/me/ai-subscriptions/chatgpt/login/poll", %{login_id: "login-1"})
             |> json_response(200)

    assert_push "snapshot", %{subscriptions: pushed}
    assert %{"connected" => true, "runs_threads" => true} = provider(pushed, "chatgpt")

    assert authorized(bearer)
           |> delete("/api/me/ai-subscriptions/chatgpt/login?login_id=login-1")
           |> response(204)

    assert_received {:tuist, "DELETE", "/api/me/ai-subscriptions/chatgpt/login",
                     "login_id=login-1", _}

    assert %{"subscriptions" => _} =
             authorized(bearer) |> delete("/api/me/ai-subscriptions/claude") |> json_response(200)

    assert_push "snapshot", %{subscriptions: pushed}
    refute provider(pushed, "claude")["connected"]

    # Only the two providers, never an arbitrary upstream path.
    assert authorized(bearer) |> delete("/api/me/ai-subscriptions/other") |> json_response(404)
    refute_received {:tuist, "DELETE", "/api/me/ai-subscriptions/other", _, _}
  end

  test "the channel shows changes made elsewhere when it reads Tuist again", %{
    bearer: bearer,
    state: state
  } do
    {:ok, socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})
    {:ok, _reply, joined} = subscribe_and_join(socket, "ai_subscriptions")

    # Unchanged: nothing is pushed.
    send(joined.channel_pid, :poll)
    refute_push "snapshot", _

    # Connected on Tuist's settings page.
    Agent.update(state, &%{&1 | chatgpt: true})
    send(joined.channel_pid, :poll)
    assert_push "snapshot", %{subscriptions: pushed}
    assert provider(pushed, "chatgpt")["connected"]
  end

  defp list(state) do
    saved = Agent.get(state, & &1)

    %{
      subscriptions:
        for provider <- [:claude, :chatgpt] do
          %{
            provider: provider,
            connected: saved[provider],
            updated_at: nil,
            login_available: true
          }
        end
    }
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
