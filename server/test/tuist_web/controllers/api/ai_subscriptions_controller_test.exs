defmodule TuistWeb.API.AISubscriptionsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.UserAISubscription
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @claude_token "sk-ant-oat01-" <> String.duplicate("a1B2_c3-", 8)
  @base "/api/me/ai-subscriptions"

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Environment, :chatgpt_client_id, fn -> "app_test_client" end)
    {:ok, bearer, _claims} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")

    %{user: user, bearer: bearer}
  end

  defp authorized(conn, bearer) do
    conn
    |> put_req_header("authorization", "Bearer #{bearer}")
    |> put_req_header("content-type", "application/json")
  end

  defp sign_in_oauth(user, client) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    bearer
  end

  test "connects, lists and disconnects Claude without returning the token", %{user: user, bearer: bearer} do
    conn = build_conn() |> authorized(bearer) |> get(@base)

    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert %{
             "subscriptions" => [
               %{"provider" => "claude", "connected" => false, "updated_at" => nil, "login_available" => true},
               %{"provider" => "chatgpt", "connected" => false, "login_available" => true}
             ]
           } = json_response(conn, 200)

    conn = build_conn() |> authorized(bearer) |> put("#{@base}/claude", %{token: @claude_token})

    assert %{"subscriptions" => [%{"provider" => "claude", "connected" => true, "updated_at" => updated_at}, _]} =
             json_response(conn, 200)

    assert {:ok, _, _} = DateTime.from_iso8601(updated_at)
    refute response(conn, 200) =~ "sk-ant-oat01"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert {:ok, %{access_token: @claude_token}} = AISubscriptions.credentials(user, :claude)

    assert %{"subscriptions" => [%{"provider" => "claude", "connected" => false}, _]} =
             build_conn() |> authorized(bearer) |> delete("#{@base}/claude") |> json_response(200)

    assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)
  end

  test "rejects tokens that are not Claude subscription tokens", %{bearer: bearer} do
    for token <- ["sk-ant-api03-" <> String.duplicate("a", 40), "nope"] do
      conn = build_conn() |> authorized(bearer) |> put("#{@base}/claude", %{token: token})
      assert %{"message" => message} = json_response(conn, 422)
      refute message =~ token
    end

    assert build_conn() |> authorized(bearer) |> put("#{@base}/claude", %{}) |> json_response(422)
    assert build_conn() |> authorized(bearer) |> delete("#{@base}/openai") |> json_response(422)
  end

  test "signs in to ChatGPT and returns only the user-facing sign-in details", %{user: user, bearer: bearer} do
    stub_openai(approved?: false)

    conn = build_conn() |> authorized(bearer) |> post("#{@base}/chatgpt/login")

    assert %{
             "login_id" => login_id,
             "user_code" => "ABCD-1234",
             "verification_url" => "https://auth.openai.com/codex/device",
             "interval" => 5,
             "expires_at" => expires_at
           } = body = json_response(conn, 200)

    assert map_size(body) == 5
    refute response(conn, 200) =~ "dev-1"
    assert {:ok, _, _} = DateTime.from_iso8601(expires_at)

    poll = fn id -> build_conn() |> authorized(bearer) |> post("#{@base}/chatgpt/login/poll", %{login_id: id}) end

    assert %{"status" => "pending"} = login_id |> poll.() |> json_response(200)
    assert Ecto.UUID.generate() |> poll.() |> json_response(404)

    allow_next_poll(user)
    stub_openai(approved?: true)
    conn = poll.(login_id)
    assert %{"status" => "connected"} = json_response(conn, 200)
    refute response(conn, 200) =~ "access-1"

    assert %{"subscriptions" => [_, %{"provider" => "chatgpt", "connected" => true}]} =
             build_conn() |> authorized(bearer) |> get(@base) |> json_response(200)
  end

  test "cancels a pending ChatGPT sign-in", %{bearer: bearer} do
    stub_openai(approved?: false)

    %{"login_id" => login_id} =
      build_conn() |> authorized(bearer) |> post("#{@base}/chatgpt/login") |> json_response(200)

    assert build_conn() |> authorized(bearer) |> delete("#{@base}/chatgpt/login?login_id=#{login_id}") |> response(204)

    assert build_conn()
           |> authorized(bearer)
           |> delete("#{@base}/chatgpt/login?login_id=#{login_id}")
           |> json_response(404)

    assert build_conn()
           |> authorized(bearer)
           |> post("#{@base}/chatgpt/login/poll", %{login_id: login_id})
           |> json_response(404)
  end

  test "maps ChatGPT sign-in failures to statuses", %{user: user, bearer: bearer} do
    start = fn -> build_conn() |> authorized(bearer) |> post("#{@base}/chatgpt/login") end
    poll = fn id -> build_conn() |> authorized(bearer) |> post("#{@base}/chatgpt/login/poll", %{login_id: id}) end

    stub(Req, :post, fn _opts -> {:ok, %Req.Response{status: 500, body: %{"detail" => "upstream-detail"}}} end)
    conn = start.()
    assert %{"message" => _} = json_response(conn, 502)
    refute response(conn, 502) =~ "upstream-detail"

    stub(Environment, :chatgpt_client_id, fn -> nil end)
    assert json_response(start.(), 503)
    stub(Environment, :chatgpt_client_id, fn -> "app_test_client" end)

    # OpenAI rejects the device code outright.
    stub_openai(approved?: false)
    %{"login_id" => login_id} = json_response(start.(), 200)
    allow_next_poll(user)
    stub(Req, :post, fn _opts -> {:ok, %Req.Response{status: 400, body: %{}}} end)
    assert login_id |> poll.() |> json_response(502)

    stub_openai(approved?: false)
    %{"login_id" => login_id} = json_response(start.(), 200)

    Repo.update_all(
      from(c in UserAISubscription, where: c.user_id == ^user.id and c.provider == :chatgpt),
      set: [pending_expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )

    assert login_id |> poll.() |> json_response(410)

    # Five sign-in attempts per five minutes, counting the ones above.
    stub_openai(approved?: false)
    assert json_response(start.(), 200)
    assert json_response(start.(), 429)
  end

  test "is not found for users without the ai flag", %{bearer: bearer} do
    stub(FeatureFlags, :ai_enabled?, fn _user -> false end)

    for request <- [
          &get(&1, @base),
          &put(&1, "#{@base}/claude", %{token: @claude_token}),
          &post(&1, "#{@base}/chatgpt/login"),
          &delete(&1, "#{@base}/claude")
        ] do
      assert build_conn() |> authorized(bearer) |> request.() |> json_response(404)
    end

    assert Repo.all(UserAISubscription) == []
  end

  test "accepts the signed-in Tuist app", %{user: user} do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    bearer = sign_in_oauth(user, Clients.public!())

    assert %{"subscriptions" => [_, _]} = build_conn() |> authorized(bearer) |> get(@base) |> json_response(200)
  end

  test "rejects account tokens, project tokens and other OAuth clients", %{user: user} do
    {:ok, {_, account_token}} =
      Accounts.create_account_token(%{account: user.account, scopes: ["account:cache:read"], name: "ai-test-token"})

    project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture(account_id: user.account.id)

    # A client registered through dynamic client registration, such as an MCP client the user authorized.
    {:ok, other_client} = Clients.create_client(%{redirect_uris: ["https://example.com/callback"], name: "other"})
    other_client_bearer = sign_in_oauth(user, other_client)

    for bearer <- [account_token, project.token, other_client_bearer],
        request <- [
          &get(&1, @base),
          # Rejected before its body is validated.
          &put(&1, "#{@base}/claude", %{unknown: true}),
          &put(&1, "#{@base}/claude", %{token: @claude_token}),
          &post(&1, "#{@base}/chatgpt/login"),
          &delete(&1, "#{@base}/claude")
        ] do
      assert build_conn() |> authorized(bearer) |> request.() |> json_response(403)
    end

    assert Repo.all(UserAISubscription) == []
    assert build_conn() |> get(@base) |> json_response(401)
  end

  defp stub_openai(approved?: approved?) do
    stub(Req, :post, fn opts ->
      case {opts[:url], opts[:form][:grant_type]} do
        {"https://auth.openai.com/api/accounts/deviceauth/usercode", _} ->
          {:ok,
           %Req.Response{status: 200, body: %{"device_auth_id" => "dev-1", "user_code" => "ABCD-1234", "interval" => 5}}}

        {"https://auth.openai.com/api/accounts/deviceauth/token", _} when approved? ->
          {:ok, %Req.Response{status: 200, body: %{"authorization_code" => "code-1", "code_verifier" => "verifier-1"}}}

        {"https://auth.openai.com/api/accounts/deviceauth/token", _} ->
          {:ok, %Req.Response{status: 403, body: %{}}}

        {"https://auth.openai.com/oauth/token", "authorization_code"} ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{"access_token" => "access-1", "refresh_token" => "refresh-1", "expires_in" => 3600}
           }}
      end
    end)
  end

  defp allow_next_poll(user) do
    Repo.update_all(
      from(c in UserAISubscription, where: c.user_id == ^user.id and c.provider == :chatgpt),
      set: [next_poll_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )
  end
end
