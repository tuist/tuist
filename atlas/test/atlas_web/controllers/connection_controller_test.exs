defmodule AtlasWeb.ConnectionControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.PushFixtures, only: [native_access_token: 1, native_access_token: 2]

  alias Atlas.Audit.Activity
  alias Atlas.Connections
  alias Atlas.Connections.Authorization
  alias Atlas.Connections.Config
  alias Atlas.Connections.Connection
  alias Atlas.Repo

  setup do
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    stub(AtlasWeb.NativeLinks.Config, :origin, fn -> "https://atlas.test" end)
    :ok
  end

  test "connections require login", %{conn: conn} do
    assert conn |> get(~p"/connections/github/authorize") |> redirected_to() == "/login"
    assert conn |> get(~p"/connections/github/callback?code=code&state=state") |> redirected_to() == "/login"
  end

  test "Phoenix filters native tickets, provider codes, state and PKCE values from request logs" do
    params = Map.new(~w(native code state verifier code_verifier code_challenge nonce), &{&1, "private-#{&1}"})
    filtered = Phoenix.Logger.filter_values(Map.put(params, "provider", "github"))
    assert filtered["provider"] == "github"
    for key <- Map.keys(params), do: assert(filtered[key] == "[FILTERED]")
  end

  test "provider consent uses personal scopes, PKCE, and offline Google access", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    for provider <- ~w(github slack google) do
      response = get(conn, "/connections/#{provider}/authorize")
      uri = URI.parse(redirected_to(response))
      params = URI.decode_query(uri.query)
      assert params["redirect_uri"] =~ "/connections/#{provider}/callback"
      assert params["client_id"] == "test-client"
      assert is_binary(params["state"])
      refute Map.has_key?(params, "client_secret")

      if provider == "slack" do
        assert params["user_scope"] == "search:read,chat:write"
        refute Map.has_key?(params, "scope")
      else
        pending = get_session(response, :account_connection)
        assert params["code_challenge"] == Base.url_encode64(:crypto.hash(:sha256, pending.verifier), padding: false)
        assert params["code_challenge_method"] == "S256"
      end

      if provider == "github", do: assert(params["scope"] == "offline_access")

      if provider == "google" do
        assert params["access_type"] == "offline"
        assert params["prompt"] == "consent"
        assert params["scope"] =~ "drive.file"
        assert params["scope"] =~ "calendar.readonly"
        refute params["scope"] =~ "calendar.events"
        refute params["scope"] =~ "gmail"
      end
    end
  end

  test "Google scope ownership stays in the provider and ignores arbitrary scope escalation", %{conn: conn} do
    {conn, _} = log_in_user(conn)
    response = get(conn, ~p"/connections/google/authorize?calendar_access=write")
    params = response |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    refute params["scope"] =~ "https://www.googleapis.com/auth/calendar.events"
    assert params["scope"] =~ "https://www.googleapis.com/auth/calendar.readonly"
    refute params["scope"] =~ "https://www.googleapis.com/auth/calendar "
  end

  test "callback completes the connection once and retains the Atlas login", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    response = get(conn, ~p"/connections/github/authorize")

    params = response |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    state = params["state"]
    pending = get_session(response, :account_connection)

    stub(Req, :request, fn opts ->
      body =
        if opts[:method] == :post do
          assert opts[:form] == %{
                   "client_id" => "test-client",
                   "client_secret" => "test-secret",
                   "code" => "code",
                   "code_verifier" => pending.verifier,
                   "grant_type" => "authorization_code",
                   "redirect_uri" => params["redirect_uri"]
                 }

          %{"access_token" => "secret", "expires_in" => 28_800, "refresh_token" => "refresh", "scope" => ""}
        else
          assert opts[:auth] == {:bearer, "secret"}
          %{"id" => 123, "login" => "octocat"}
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end)

    completed = response |> recycle() |> get(~p"/connections/github/callback?code=code&state=#{state}")
    assert redirected_to(completed) == "/settings/connections"
    assert get_session(completed, :user_id) == user.id
    assert get_session(completed, :account_connection) == nil
    assert {:ok, "secret"} = Connections.access_token(user, "github")

    replay = completed |> recycle() |> get(~p"/connections/github/callback?code=code&state=#{state}")
    assert Phoenix.Flash.get(replay.assigns.flash, :error)

    stub(Req, :request, fn _ -> flunk("An old signed cookie cannot replay a consumed authorization") end)
    replay = response |> recycle() |> get(~p"/connections/github/callback?code=code&state=#{state}")
    assert Phoenix.Flash.get(replay.assigns.flash, :error)
  end

  test "state is bound to the initiating user, browser session, provider, and expiration", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    response = get(conn, ~p"/connections/github/authorize")

    state =
      response |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")

    pending = get_session(response, :account_connection)
    stub(Req, :request, fn _ -> flunk("invalid callbacks must never exchange a code") end)

    {other_conn, _} = log_in_user(build_conn())

    attempts = [
      {other_conn, state, "github"},
      {conn, state, "github"},
      {recycle(response), state, "slack"},
      {recycle(response), "tampered", "github"},
      {recycle(response),
       Phoenix.Token.sign(
         AtlasWeb.Endpoint,
         "personal-account-connection",
         %{user_id: user.id, provider: "github", nonce: pending.nonce},
         signed_at: System.os_time(:second) - 601
       ), "github"}
    ]

    for {attempt_conn, attempt_state, provider} <- attempts do
      result = get(attempt_conn, "/connections/#{provider}/callback", %{code: "code", state: attempt_state})
      assert redirected_to(result) == "/settings/connections"
      assert Phoenix.Flash.get(result.assigns.flash, :error)
    end

    assert {:error, :not_connected} = Connections.access_token(user, "github")
  end

  test "cancelled consent and unconfigured providers fail without creating a grant", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    response = get(conn, ~p"/connections/google/authorize")

    state =
      response |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")

    cancelled = response |> recycle() |> get(~p"/connections/google/callback?error=access_denied&state=#{state}")
    assert redirected_to(cancelled) == "/settings/connections"
    assert {:error, :not_connected} = Connections.access_token(user, "google")
    assert conn |> get(~p"/connections/unknown/authorize") |> redirected_to() == "/settings/connections"
  end

  test "API requires a bearer even with a browser login, including native prepare", %{conn: conn} do
    {browser, _user} = log_in_user(conn)

    for {method, path} <- [
          {:get, "/api/me/connections"},
          {:delete, "/api/me/connections/github"},
          {:post, "/api/me/connections/github/authorize"}
        ] do
      response = dispatch(browser, @endpoint, method, path, %{"state" => native_nonce()})
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "only native client tokens can prepare an authorization", %{conn: conn} do
    {_browser, user} = log_in_user(conn)

    for redirects <- [["https://example.com/callback"], ["dev.tuist.atlas://oauth-callback", "https://example.com/cb"]] do
      {_client, token} = native_access_token(user, redirects)
      api = bearer(token)
      assert api |> get("/api/me/connections") |> json_response(200)

      assert api |> post("/api/me/connections/github/authorize", %{"state" => native_nonce()}) |> json_response(403) ==
               %{"error" => "native_client_required"}
    end
  end

  test "API lists only caller metadata and disconnect is owner scoped and idempotent", %{conn: conn} do
    {_browser, user} = log_in_user(conn)
    {_other_browser, other} = log_in_user(build_conn())
    connection = insert_connection!(user)
    {_client, token} = native_access_token(user)
    {_client, other_token} = native_access_token(other)
    api = bearer(token)

    listing = get(api, "/api/me/connections", %{user_id: other.id})

    assert %{"connections" => [%{"account_name" => "octocat", "status" => "connected"} | _]} =
             json_response(listing, 200)

    assert get_resp_header(listing, "cache-control") == ["no-store"]
    refute listing.resp_body =~ "private-access"
    refute listing.resp_body =~ "private-refresh"
    refute listing.resp_body =~ "access_token"
    refute listing.resp_body =~ "refresh_token"

    other_listing = bearer(other_token) |> get("/api/me/connections") |> json_response(200)
    assert Enum.all?(other_listing["connections"], &(&1["status"] == "not_connected"))

    assert bearer(other_token) |> delete("/api/me/connections/github") |> json_response(200) == %{
             "disconnected" => true
           }

    assert Repo.get!(Connection, connection.id)

    for _ <- 1..2 do
      assert api |> delete("/api/me/connections/github") |> json_response(200) == %{"disconnected" => true}
    end

    assert Repo.get(Connection, connection.id) == nil
    activity = Repo.get_by!(Activity, action: "connection.disconnected", target_id: connection.id)
    assert activity.actor_id == user.id
    assert activity.interface == "api"
    refute inspect(activity) =~ "private-access"
    refute inspect(activity) =~ "private-refresh"
  end

  test "prepare binds signed ticket to user, provider, client and native state without trusting host or redirects", %{
    conn: conn
  } do
    {_browser, user} = log_in_user(conn)
    {client_id, token} = native_access_token(user)
    state = native_nonce()

    response =
      token
      |> bearer()
      |> put_req_header("x-forwarded-host", "evil.example")
      |> post("/api/me/connections/github/authorize", %{"state" => state})

    assert %{"authorization_url" => url} = json_response(response, 200)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert %URI{scheme: "https", host: "atlas.test", path: "/connections/github/authorize"} = URI.parse(url)
    %{"native" => ticket} = query(url)

    assert {:ok, %{user_id: user_id, provider: "github", client_id: ^client_id, state: ^state}} =
             Phoenix.Token.verify(@endpoint, "native-account-connection", ticket, max_age: 600)

    assert user_id == user.id
    refute url =~ token

    for body <- [
          %{},
          %{"state" => "short"},
          %{"state" => String.duplicate("!", 43)},
          %{"state" => [state]},
          %{"state" => state, "redirect_uri" => "https://evil.example"},
          %{"state" => state, "user_id" => user.id}
        ] do
      assert token |> bearer() |> post("/api/me/connections/github/authorize", body) |> json_response(422) ==
               %{"error" => "invalid_connection_authorization"}
    end

    assert token |> bearer() |> post("/api/me/connections/unknown/authorize", %{"state" => state}) |> json_response(422)
    stub(AtlasWeb.NativeLinks.Config, :origin, fn -> nil end)
    assert token |> bearer() |> post("/api/me/connections/github/authorize", %{"state" => state}) |> json_response(422)
  end

  test "native ticket never authenticates a browser or permits cross-user or cross-provider linking", %{conn: conn} do
    {browser, user} = log_in_user(conn)
    {_client_id, token} = native_access_token(user)
    {_url, ticket} = prepare(token, "github", native_nonce())
    {other_browser, _other} = log_in_user(build_conn())
    stub(Req, :request, fn _ -> flunk("Invalid browser/ticket must not call a provider") end)

    signed_out = get(build_conn(), "/connections/github/authorize", %{native: ticket})
    assert redirected_to(signed_out) == "/login"
    assert get_session(signed_out, :user_id) == nil

    {:ok, context} = Phoenix.Token.verify(@endpoint, "native-account-connection", ticket, max_age: 600)

    expired =
      Phoenix.Token.sign(@endpoint, "native-account-connection", context, signed_at: System.os_time(:second) - 601)

    for {attempt, provider, native} <- [
          {other_browser, "github", ticket},
          {browser, "slack", ticket},
          {browser, "github", "tampered"},
          {browser, "github", expired},
          {browser, "github", %{"malformed" => ticket}}
        ] do
      result = get(attempt, "/connections/#{provider}/authorize", %{native: native})
      assert redirected_to(result) == "/settings/connections"
      assert get_session(result, :account_connection) == nil
    end

    assert Repo.aggregate(Connection, :count) == 0
    assert Repo.aggregate(Authorization, :count) == 0
  end

  test "native success uses fixed callback, isolated provider state and PKCE, and resists old-cookie replay", %{
    conn: conn
  } do
    {browser, user} = log_in_user(conn)
    {client_id, token} = native_access_token(user)

    for provider <- ~w(github slack google) do
      state = native_nonce()
      {_url, ticket} = prepare(token, provider, state)

      consent =
        get(browser, "/connections/#{provider}/authorize", %{native: ticket, redirect_uri: "https://evil.example"})

      params = query(redirected_to(consent))
      pending = get_session(consent, :account_connection)
      assert pending.native == %{user_id: user.id, provider: provider, client_id: client_id, state: state}
      refute params["state"] in [ticket, state]
      assert pending.verifier != state

      stub(Req, :request, fn opts ->
        assert opts[:redirect] == false
        assert opts[:retry] == false

        body =
          case opts[:url] do
            "https://github.com/login/oauth/access_token" ->
              %{"access_token" => "private-access", "refresh_token" => "private-refresh"}

            "https://api.github.com/user" ->
              %{"id" => 42, "login" => "octocat"}

            "https://slack.com/api/oauth.v2.access" ->
              %{"authed_user" => %{"access_token" => "private-access", "token_type" => "user"}}

            "https://slack.com/api/auth.test" ->
              %{"user_id" => "U42", "user" => "octocat", "team_id" => "T42"}

            "https://oauth2.googleapis.com/token" ->
              %{"access_token" => "private-access", "refresh_token" => "private-refresh"}

            "https://www.googleapis.com/oauth2/v3/userinfo" ->
              %{"sub" => "42", "email" => "octocat@example.com"}
          end

        if opts[:method] == :post and provider != "slack", do: assert(opts[:form]["code_verifier"] == pending.verifier)
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      completed =
        consent |> recycle() |> get("/connections/#{provider}/callback", %{state: params["state"], code: "code"})

      assert_native_result(completed, state, provider, "connected")
      assert get_session(completed, :user_id) == user.id
      assert get_session(completed, :account_connection) == nil
      assert {:ok, "private-access"} = Connections.access_token(user, provider)
      refute inspect(get_session(completed)) =~ "private-access"

      stub(Req, :request, fn _ -> flunk("A consumed provider state cannot exchange twice") end)
      replay = consent |> recycle() |> get("/connections/#{provider}/callback", %{state: params["state"], code: "code"})
      assert_native_result(replay, state, provider, "error")
    end
  end

  test "native denial, provider failure and unavailable configuration return only a bounded error", %{conn: conn} do
    {browser, user} = log_in_user(conn)
    {_client_id, token} = native_access_token(user)

    for provider <- ~w(github slack google), failure <- [:denied, :failed, :unconfigured] do
      state = native_nonce()
      {_url, ticket} = prepare(token, provider, state)
      consent = get(browser, "/connections/#{provider}/authorize", %{native: ticket})
      provider_state = query(redirected_to(consent))["state"]
      stub(Req, :request, fn _ -> {:ok, %Req.Response{status: 503, body: "private-provider-error"}} end)
      if failure == :unconfigured, do: stub(Config, :credentials, fn _ -> %{} end)

      params =
        if failure == :denied,
          do: %{state: provider_state, error: "access_denied"},
          else: %{state: provider_state, code: "code"}

      completed = consent |> recycle() |> get("/connections/#{provider}/callback", params)
      assert_native_result(completed, state, provider, "error")
      stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    end

    state = native_nonce()
    {_url, ticket} = prepare(token, "github", state)
    stub(Config, :credentials, fn _ -> %{} end)
    unavailable = get(browser, "/connections/github/authorize", %{native: ticket})
    assert_native_result(unavailable, state, "github", "error")
    assert Repo.aggregate(Connection, :count) == 0
  end

  test "expired provider state or durable nonce cannot link and switched browser users cannot finish", %{conn: conn} do
    {browser, user} = log_in_user(conn)
    {_client, token} = native_access_token(user)
    state = native_nonce()
    {_url, ticket} = prepare(token, "github", state)
    consent = get(browser, "/connections/github/authorize", %{native: ticket})
    pending = get_session(consent, :account_connection)
    provider_state = query(redirected_to(consent))["state"]
    stub(Req, :request, fn _ -> flunk("Invalid or expired state must not exchange tokens") end)

    expired =
      Phoenix.Token.sign(@endpoint, "personal-account-connection", Map.take(pending, [:user_id, :provider, :nonce]),
        signed_at: System.os_time(:second) - 601
      )

    consent
    |> recycle()
    |> get("/connections/github/callback", %{state: expired, code: "code"})
    |> assert_native_result(state, "github", "error")

    {other, _user} = log_in_user(recycle(consent))
    switched = get(other, "/connections/github/callback", %{state: provider_state, code: "code"})
    assert redirected_to(switched) == "/settings/connections"

    authorization = Repo.get!(Authorization, :crypto.hash(:sha256, pending.nonce))

    Repo.update!(
      Ecto.Changeset.change(authorization,
        expires_at: DateTime.utc_now() |> DateTime.add(-1) |> DateTime.truncate(:second)
      )
    )

    consent
    |> recycle()
    |> get("/connections/github/callback", %{state: provider_state, code: "code"})
    |> assert_native_result(state, "github", "error")

    assert Repo.aggregate(Connection, :count) == 0
  end

  defp native_nonce, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp bearer(token), do: build_conn() |> put_req_header("authorization", "Bearer #{token}")
  defp query(url), do: url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

  defp prepare(token, provider, state) do
    response = token |> bearer() |> post("/api/me/connections/#{provider}/authorize", %{"state" => state})
    %{"authorization_url" => url} = json_response(response, 200)
    {url, query(url)["native"]}
  end

  defp assert_native_result(conn, state, provider, status) do
    url = redirected_to(conn)
    assert %URI{scheme: "dev.tuist.atlas", host: "connections-callback", path: path} = URI.parse(url)
    assert path in [nil, ""]
    assert query(url) == %{"state" => state, "provider" => provider, "status" => status}
    refute url =~ "private-access"
    refute url =~ "private-refresh"
    refute url =~ "private-provider-error"
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
