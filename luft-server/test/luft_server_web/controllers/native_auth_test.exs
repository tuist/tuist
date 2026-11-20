defmodule LuftServerWeb.NativeAuthTest do
  use LuftServerWeb.ConnCase, async: true

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias LuftServer.FakeTuist
  alias LuftServer.NativeAuth
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Sessions.Session
  alias LuftServerWeb.AuthController
  alias LuftServerWeb.NativeAuthController
  alias Plug.Crypto.KeyGenerator

  @verifier String.duplicate("a", 43)

  defp request(redirect \\ "luft://oauth-callback") do
    %{
      "response_type" => "code",
      "client_id" => NativeAuth.client_id(),
      "redirect_uri" => redirect,
      "state" => "native-state",
      "code_challenge_method" => "S256",
      "code_challenge" => :sha256 |> :crypto.hash(@verifier) |> Base.url_encode64(padding: false)
    }
  end

  defp login(conn, provider, request \\ request()) do
    login = conn |> init_test_session(%{}) |> NativeAuthController.authorize(request)
    transaction = get_session(login, :signin)
    {code, query} = FakeTuist.authorize(provider, redirected_to(login))

    callback =
      build_conn()
      |> init_test_session(%{signin: transaction})
      |> AuthController.callback(%{"state" => query["state"], "code" => code})

    {callback, transaction, code}
  end

  defp exchange_params(callback, redirect \\ "luft://oauth-callback") do
    query = callback |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["state"] == "native-state"
    assert is_binary(query["code"])
    refute Map.has_key?(query, "access_token")
    refute Map.has_key?(query, "refresh_token")

    %{
      "grant_type" => "authorization_code",
      "client_id" => NativeAuth.client_id(),
      "redirect_uri" => redirect,
      "code" => query["code"],
      "code_verifier" => @verifier
    }
  end

  test "native OIDC completion, single-use exchange, rotating refresh, escrow and logout", %{
    conn: conn
  } do
    provider = FakeTuist.stub()
    {callback, transaction, upstream_code} = login(conn, provider)
    refute Map.has_key?(callback.resp_cookies, "__Host-Http-luft_session")
    refute Map.has_key?(callback.resp_cookies, "luft_session")
    params = exchange_params(callback)
    assert {:ok, credentials} = NativeAuth.exchange(params)
    assert credentials.expires_in in 3599..3600
    assert {:error, :invalid_grant} = NativeAuth.exchange(params)
    assert session = NativeAuth.resolve_bearer(credentials.access_token)
    assert session.user_sub == "42"
    assert {:ok, "access-1"} = Sessions.access_token(session)
    refute session.access_token == "access-1"
    refute session.refresh_token == "refresh-1"
    assert nil == NativeAuth.resolve_bearer(credentials.refresh_token)
    assert nil == NativeAuth.resolve_bearer(params["code"])
    assert nil == NativeAuth.resolve_bearer("access-1")

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => NativeAuth.client_id(),
      "refresh_token" => credentials.refresh_token
    }

    assert {:ok, rotated} = NativeAuth.exchange(refresh)
    refute rotated.refresh_token == credentials.refresh_token
    refute rotated.access_token == credentials.access_token
    # A response lost after rotation can be retried without losing the session.
    assert {:ok, ^rotated} = NativeAuth.exchange(refresh)

    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [refresh_replay_expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
    )

    assert {:error, :invalid_grant} = NativeAuth.exchange(refresh)

    replay =
      build_conn()
      |> init_test_session(%{signin: transaction})
      |> AuthController.callback(%{"state" => transaction["state"], "code" => upstream_code})

    assert json_response(replay, 400)["error"] == "invalid_state"

    logout = build_conn() |> assign(:session, session) |> AuthController.logout(%{})
    assert logout.status == 204
    assert nil == NativeAuth.resolve_bearer(rotated.access_token)

    assert {:error, :invalid_grant} =
             NativeAuth.exchange(%{refresh | "refresh_token" => rotated.refresh_token})

    assert {:error, :invalid_grant} = NativeAuth.exchange(refresh)
  end

  test "loopback exchange is bound to client, exact redirect and PKCE", %{conn: conn} do
    {callback, _, _} = login(conn, FakeTuist.stub(), request("http://127.0.0.1:54321/callback"))
    params = exchange_params(callback, "http://127.0.0.1:54321/callback")

    for bad <- [
          %{"client_id" => "other"},
          %{"redirect_uri" => "http://127.0.0.1:54322/callback"},
          %{"code_verifier" => String.duplicate("b", 43)},
          %{"code" => params["code"] <> "x"}
        ] do
      assert {:error, :invalid_grant} = NativeAuth.exchange(Map.merge(params, bad))
    end

    assert {:ok, _} = NativeAuth.exchange(params)
  end

  test "rejects unregistered redirects and invalid authorization requests", %{conn: conn} do
    for uri <- [
          "https://evil.test/callback",
          "luft://oauth-callback?next=evil",
          "http://localhost:1234/callback",
          "http://127.0.0.1:1234/callback?x=1",
          "http://127.0.0.1:1234/callback#x",
          "http://evil@127.0.0.1:1234/callback",
          "http://127.0.0.1:0/callback",
          "http://127.0.0.1:1234/other"
        ] do
      assert {:error, :invalid_request} = NativeAuth.validate_request(request(uri))
    end

    for bad <- [
          %{"client_id" => "bad"},
          %{"code_challenge_method" => "plain"},
          %{"state" => ""},
          %{"scope" => "openid"},
          %{"response_type" => "token"}
        ] do
      response =
        conn
        |> init_test_session(%{})
        |> NativeAuthController.authorize(Map.merge(request(), bad))

      assert json_response(response, 400)["error"] == "invalid_request"
    end

    for port <- [1, 80, 99, 100, 54_321, 65_535] do
      assert {:ok, _} = NativeAuth.validate_request(request("http://127.0.0.1:#{port}/callback"))
    end
  end

  test "pending sign-ins expire and cannot be replayed", %{conn: conn} do
    provider = FakeTuist.stub()
    login = conn |> init_test_session(%{}) |> NativeAuthController.authorize(request())
    transaction = get_session(login, :signin)
    {code, query} = FakeTuist.authorize(provider, redirected_to(login))

    Repo.update_all(from(s in Session, where: s.user_sub == "native-pending"),
      set: [expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
    )

    response =
      build_conn()
      |> init_test_session(%{signin: transaction})
      |> AuthController.callback(%{"state" => query["state"], "code" => code})

    assert json_response(response, 400)["error"] == "invalid_state"
  end

  test "expired sessions invalidate both token types", %{conn: conn} do
    {callback, _, _} = login(conn, FakeTuist.stub())
    assert {:ok, credentials} = NativeAuth.exchange(exchange_params(callback))
    session = NativeAuth.resolve_bearer(credentials.access_token)

    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
    )

    assert nil == NativeAuth.resolve_bearer(credentials.access_token)

    assert {:error, :invalid_grant} =
             NativeAuth.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => NativeAuth.client_id(),
               "refresh_token" => credentials.refresh_token
             })
  end

  test "native flow retains all OIDC verification", %{conn: conn} do
    for claims <- [%{"nonce" => "wrong"}, %{"aud" => "wrong"}, %{"iss" => "wrong"}, %{"exp" => 1}] do
      {callback, _, _} = login(conn, FakeTuist.stub(claims: claims))
      assert json_response(callback, 502)["error"] == "sign_in_failed"
    end
  end

  test "social selection forwards to Tuist and discovery names the Luft public client", %{
    conn: conn
  } do
    FakeTuist.stub()

    for provider <- [:apple, :google, :github] do
      response = apply(NativeAuthController, provider, [init_test_session(conn, %{}), request()])
      assert URI.parse(redirected_to(response)).path == "/oauth2/#{provider}"
    end

    assert json_response(NativeAuthController.discovery(conn, %{}), 200) ==
             %{"luft_oauth_client_id" => NativeAuth.client_id()}
  end

  test "authorization codes expire without exposing credentials and token responses are not cacheable",
       %{
         conn: conn
       } do
    {callback, _, _} = login(conn, FakeTuist.stub())
    params = exchange_params(callback)

    Repo.update_all(from(t in Token, where: t.value == ^params["code"]),
      set: [expires_at: System.system_time(:second) - 1]
    )

    assert {:error, :invalid_grant} = NativeAuth.exchange(params)
    assert {:error, :invalid_grant} = NativeAuth.exchange(%{params | "code" => %{}})

    {callback, _, _} = login(conn, FakeTuist.stub())
    response = post(build_conn(), "/oauth2/token", exchange_params(callback))
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert get_resp_header(response, "pragma") == ["no-cache"]
    credentials = json_response(response, 200)
    refute response.resp_body =~ "access-1"
    refute response.resp_body =~ "refresh-1"
    assert %Session{} = NativeAuth.resolve_bearer(credentials["access_token"])
  end

  test "access verification checks signature, expiry, audience, issuer and session binding", %{
    conn: conn
  } do
    {callback, _, _} = login(conn, FakeTuist.stub())
    {:ok, credentials} = NativeAuth.exchange(exchange_params(callback))
    %JOSE.JWT{fields: claims} = JOSE.JWT.peek_payload(credentials.access_token)
    secret = Application.fetch_env!(:luft_server, @endpoint)[:secret_key_base]

    key =
      secret
      |> KeyGenerator.generate("luft native access signing v1", length: 32)
      |> JOSE.JWK.from_oct()

    for invalid <- [
          %{"exp" => System.system_time(:second) - 1},
          %{"aud" => "other"},
          %{"iss" => "other"},
          %{"sub" => "other"},
          %{"type" => "refresh"},
          %{"sid" => "not-a-uuid"}
        ] do
      {_, token} =
        key
        |> JOSE.JWT.sign(%{"alg" => "HS256"}, Map.merge(claims, invalid))
        |> JOSE.JWS.compact()

      assert nil == NativeAuth.resolve_bearer(token)
    end

    {_, forged} =
      "x"
      |> String.duplicate(32)
      |> JOSE.JWK.from_oct()
      |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims)
      |> JOSE.JWS.compact()

    assert nil == NativeAuth.resolve_bearer(forged)
  end

  test "concurrent code exchange spends the database credential only once", %{conn: conn} do
    {callback, _, _} = login(conn, FakeTuist.stub())
    params = exchange_params(callback)

    results =
      1..2
      |> Enum.map(fn _ -> Task.async(fn -> NativeAuth.exchange(params) end) end)
      |> Task.await_many()

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :invalid_grant}, &1)) == 1
  end

  test "concurrent refresh retries return the same pair and older generations are refused", %{
    conn: conn
  } do
    {callback, _, _} = login(conn, FakeTuist.stub())
    {:ok, credentials} = NativeAuth.exchange(exchange_params(callback))

    params = %{
      "grant_type" => "refresh_token",
      "client_id" => NativeAuth.client_id(),
      "refresh_token" => credentials.refresh_token
    }

    [first, second] =
      1..2
      |> Enum.map(fn _ -> Task.async(fn -> NativeAuth.exchange(params) end) end)
      |> Task.await_many()

    assert {:ok, rotated} = first
    assert second == first
    assert {:ok, _} = NativeAuth.exchange(%{params | "refresh_token" => rotated.refresh_token})
    assert {:error, :invalid_grant} = NativeAuth.exchange(params)
  end

  test "Boruta grant revocation immediately rejects access and refresh credentials", %{conn: conn} do
    {callback, _, _} = login(conn, FakeTuist.stub())
    {:ok, credentials} = NativeAuth.exchange(exchange_params(callback))
    token = Boruta.AccessTokensAdapter.get_by(value: credentials.access_token)
    assert {:ok, _} = Boruta.AccessTokensAdapter.revoke(token)

    rejected =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> credentials.access_token)
      |> get("/api/me")

    assert json_response(rejected, 401)["error"] == "unauthenticated"

    assert {:error, :invalid_grant} =
             NativeAuth.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => NativeAuth.client_id(),
               "refresh_token" => credentials.refresh_token
             })
  end

  test "sign-ins for the same Tuist identity have independent sessions and grant retention", %{
    conn: conn
  } do
    provider = FakeTuist.stub()
    {first_callback, _, _} = login(conn, provider)
    {:ok, first} = NativeAuth.exchange(exchange_params(first_callback))
    {second_callback, _, _} = login(conn, provider)
    {:ok, second} = NativeAuth.exchange(exchange_params(second_callback))
    first_session = NativeAuth.resolve_bearer(first.access_token)
    second_session = NativeAuth.resolve_bearer(second.access_token)
    assert first_session.user_sub == second_session.user_sub
    refute first_session.id == second_session.id

    assert response(
             AuthController.logout(assign(build_conn(), :session, first_session), %{}),
             204
           ) == ""

    assert nil == NativeAuth.resolve_bearer(first.access_token)
    assert %Session{} = NativeAuth.resolve_bearer(second.access_token)
    refute Repo.exists?(from t in Token, where: t.sub == ^first_session.id)

    Repo.update_all(from(s in Session, where: s.id == ^second_session.id),
      set: [expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
    )

    Sessions.prune()
    assert nil == NativeAuth.resolve_bearer(second.access_token)
    refute Repo.exists?(from t in Token, where: t.sub == ^second_session.id)
  end

  test "request objects in either parameter source are rejected before any HTTP fetch" do
    for source <- [:query, :body], parameter <- ["request_uri", "request"] do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(listener)

      server =
        Task.async(fn ->
          case :gen_tcp.accept(listener) do
            {:ok, socket} ->
              {:ok, _request} = :gen_tcp.recv(socket, 0, 1000)
              :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
              :gen_tcp.close(socket)
              :fetched

            closed ->
              closed
          end
        end)

      try do
        value = if parameter == "request_uri", do: "http://127.0.0.1:#{port}/private", else: ""
        params = %{parameter => value}

        response =
          case source do
            :query -> post(build_conn(), "/oauth2/token?" <> URI.encode_query(params), %{})
            :body -> post(build_conn(), "/oauth2/token", params)
          end

        # Check the listener first: a late rejection after fetching is not safe.
        :gen_tcp.close(listener)
        assert {:error, :closed} = Task.await(server)
        assert json_response(response, 400)["error"] == "invalid_request"

        for route <- ["authorize", "apple", "google", "github"] do
          response = get(build_conn(), "/oauth2/#{route}", Map.merge(request(), params))
          assert json_response(response, 400)["error"] == "invalid_request"
        end
      after
        :gen_tcp.close(listener)
      end
    end
  end
end
