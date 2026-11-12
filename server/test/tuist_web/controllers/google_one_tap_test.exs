defmodule TuistWeb.GoogleOneTapTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Plug.CSRFProtection.InvalidCSRFTokenError
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.OAuth.Google
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.GoogleOneTap

  setup_all do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public_key} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{key: key, public_key: Map.put(public_key, "kid", "google-key")}
  end

  setup do
    stub(Environment, :browser_session_isolation_enabled?, fn -> true end)
    stub(Environment, :google_auth_enabled?, fn -> true end)
    stub(Environment, :google_oauth_configured?, fn -> true end)
    stub(Environment, :google_oauth_client_id, fn -> "tuist-client" end)
    # The existing users here registered with a password on an instance that
    # confirms emails; skipping confirmation refuses to link them by email.
    stub(Environment, :skip_email_confirmation?, fn -> false end)
    %{claims: %{"sub" => "google-user", "email" => "one-tap@gmail.com", "email_verified" => true}}
  end

  @tag :session_compatibility
  test "compatible starts remain readable by the old aggregate-cookie reader", %{conn: conn, claims: claims} do
    stub(Environment, :browser_session_isolation_enabled?, fn -> false end)
    started = start(conn)
    nonce = json_response(started, 200)["nonce"]
    assert started.resp_cookies["_tuist_google_one_tap"]
    refute started.resp_cookies["_tuist_google_one_tap_" <> nonce]

    # This is the old reader's cookie API and signed aggregate wire format.
    legacy_reader =
      started
      |> recycle()
      |> Map.put(:secret_key_base, started.secret_key_base)
      |> fetch_cookies(signed: ["_tuist_google_one_tap"])

    assert [%{nonce: ^nonce}] = legacy_reader.cookies["_tuist_google_one_tap"]

    # An aggregate start can also finish on a replica with isolation enabled.
    stub(Environment, :browser_session_isolation_enabled?, fn -> true end)
    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)
    completed = started |> recycle() |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})
    assert redirected_to(completed) == "/users/choose-username"
  end

  @tag :session_compatibility
  test "an isolated start can finish on a compatible rollback replica", %{conn: conn, claims: claims} do
    started = start(conn)
    nonce = json_response(started, 200)["nonce"]
    stub(Environment, :browser_session_isolation_enabled?, fn -> false end)
    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)
    completed = started |> recycle() |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})
    assert redirected_to(completed) == "/users/choose-username"
  end

  test "issues a fresh, uncacheable session challenge", %{conn: conn} do
    conn = post(conn, "/auth/google/one-tap/start")
    assert %{"client_id" => "tuist-client", "nonce" => nonce, "csrf_token" => csrf_token} = json_response(conn, 200)
    assert byte_size(nonce) >= 32
    assert is_binary(csrf_token)
    assert [%{nonce: ^nonce}] = challenges(conn)
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "starts from a same-origin fetch whose page carried a stale CSRF token", %{conn: conn, claims: claims} do
    user = AccountsFixtures.user_fixture(email: claims["email"])

    conn =
      conn
      |> enforce_csrf()
      |> put_req_header("origin", "http://www.example.com")
      |> put_req_header("x-csrf-token", "token-from-a-cached-page")
      |> start()

    assert %{"nonce" => nonce, "csrf_token" => csrf_token} = json_response(conn, 200)
    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)

    conn =
      conn
      |> recycle()
      |> enforce_csrf()
      |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce, _csrf_token: csrf_token})

    assert redirected_to(conn) =~ "/#{user.account.name}"
    assert get_session(conn, :user_token)
  end

  test "accepts the browser's same-origin fetch metadata without an origin header", %{conn: conn} do
    conn =
      conn
      |> enforce_csrf()
      |> put_req_header("sec-fetch-site", "same-origin")
      |> start()

    assert %{"nonce" => _} = json_response(conn, 200)
  end

  test "matches the origin against the public origin forwarded by the proxy", %{conn: conn} do
    conn =
      conn
      |> enforce_csrf()
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "tuist.dev")
      |> put_req_header("origin", "https://tuist.dev")
      |> start()

    assert %{"nonce" => _} = json_response(conn, 200)
  end

  test "rejects start requests that are not provably same-origin", %{conn: conn} do
    for headers <- [
          [],
          [{"origin", "https://evil.example"}],
          [{"origin", "https://www.example.com"}],
          [{"origin", "http://www.example.com:3000"}],
          [{"origin", "http://www.example.com"}, {"x-forwarded-host", "tuist.dev"}],
          [{"sec-fetch-site", "cross-site"}],
          [{"sec-fetch-site", "same-site"}, {"origin", "http://www.example.com"}]
        ] do
      conn = Enum.reduce(headers, enforce_csrf(conn), fn {name, value}, conn -> put_req_header(conn, name, value) end)
      assert_raise InvalidCSRFTokenError, fn -> start(conn) end
    end
  end

  test "keeps the credential form CSRF-protected", %{conn: conn} do
    %{"nonce" => nonce} = conn |> start() |> json_response(200)

    assert_raise InvalidCSRFTokenError, fn ->
      conn
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("origin", "http://www.example.com")
      |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})
    end
  end

  test "logs in an existing user using the verified Google identity", %{conn: conn, claims: claims} do
    user = AccountsFixtures.user_fixture(email: claims["email"])
    conn = start(conn)
    nonce = json_response(conn, 200)["nonce"]
    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)

    conn = complete(conn, "signed-token")

    assert redirected_to(conn) =~ "/#{user.account.name}"
    assert get_session(conn, :user_token)
    refute challenges(conn)
    assert {:ok, identity} = Tuist.Accounts.get_oauth2_identity(:google, claims["sub"])
    assert identity.user.id == user.id
  end

  test "each tab's form keeps its return destination when another tab changes the session", %{conn: conn, claims: claims} do
    AccountsFixtures.user_fixture(email: claims["email"])
    first = "/first-preview?source=one+tap"

    conn = get(conn, ~p"/users/log_in?#{%{return_to: first}}")
    [action] = conn |> html_response(200) |> Floki.parse_document!() |> Floki.attribute("#google-one-tap form", "action")
    conn = conn |> recycle() |> start()
    %{"nonce" => nonce} = json_response(conn, 200)

    conn = conn |> recycle() |> get(~p"/docs/login?#{%{return_to: "/second-preview"}}")
    conn = conn |> recycle() |> start()
    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)

    conn = conn |> recycle() |> post(action, %{credential: "signed-token", nonce: nonce})

    assert get_session(conn, :user_token)
    assert redirected_to(conn) == first
  end

  test "uses the existing username selection for new users and preserves Workspace identity", %{
    conn: conn,
    claims: claims
  } do
    claims = Map.merge(claims, %{"email" => "one-tap@tuist.dev", "hd" => "tuist.dev"})
    stub(Google, :verify_identity_token, fn _, _ -> {:ok, claims} end)
    conn = conn |> start() |> complete("signed-token")

    assert redirected_to(conn) == "/users/choose-username"
    assert %{"uid" => "google-user", "provider_organization_id" => "tuist.dev"} = get_session(conn, :pending_oauth_signup)
    refute challenges(conn)
  end

  test "falls back to standard sign-in before linking a third-party email", %{conn: conn, claims: claims} do
    claims = Map.put(claims, "email", "person@example.com")
    stub(Google, :verify_identity_token, fn _, _ -> {:ok, claims} end)
    conn = conn |> start() |> complete("signed-token")
    assert redirected_to(conn) == "/users/auth/google"
    refute get_session(conn, :user_token)
  end

  test "does not require an authoritative email for an already-linked identity", %{conn: conn, claims: claims} do
    user = AccountsFixtures.user_fixture(email: "person@example.com")
    AccountsFixtures.oauth2_identity_fixture(user: user, id_in_provider: claims["sub"])
    stub(Google, :verify_identity_token, fn _, _ -> {:ok, Map.put(claims, "email", user.email)} end)
    conn = conn |> start() |> complete("signed-token")
    assert redirected_to(conn) =~ "/#{user.account.name}"
  end

  test "keeps other tabs' pending challenges after a submission consumes one", %{
    conn: conn,
    claims: claims,
    key: key,
    public_key: public_key
  } do
    signup_claims = Map.merge(claims, %{"email" => "one-tap@tuist.dev", "hd" => "tuist.dev"})
    use_public_key(public_key)

    conn = start(conn)
    nonce_a = json_response(conn, 200)["nonce"]
    conn = start(recycle(conn))
    nonce_b = json_response(conn, 200)["nonce"]
    assert Enum.sort(Enum.map(challenges(conn), & &1.nonce)) == Enum.sort([nonce_a, nonce_b])

    conn =
      conn
      |> recycle()
      |> post("/auth/google/one-tap", %{credential: signed_token(key, nonce_b, signup_claims), nonce: nonce_b})

    assert redirected_to(conn) == "/users/choose-username"
    assert [%{nonce: ^nonce_a}] = challenges(conn)
  end

  test "leaves later tabs' challenges intact when an earlier submission fails", %{
    conn: conn,
    claims: claims,
    key: key,
    public_key: public_key
  } do
    user = AccountsFixtures.user_fixture(email: claims["email"])
    use_public_key(public_key)

    conn = start(conn)
    nonce_a = json_response(conn, 200)["nonce"]
    conn = start(recycle(conn))
    nonce_b = json_response(conn, 200)["nonce"]

    failed =
      conn
      |> recycle()
      |> post("/auth/google/one-tap", %{credential: "bad-token", nonce: nonce_a})

    assert redirected_to(failed) == "/users/log_in"
    assert [%{nonce: ^nonce_b}] = challenges(failed)

    completion =
      failed
      |> recycle()
      |> post("/auth/google/one-tap", %{credential: signed_token(key, nonce_b, claims), nonce: nonce_b})

    assert redirected_to(completion) =~ "/#{user.account.name}"
    refute challenges(completion)
  end

  test "keeps the challenge when a concurrent request rewrites the session cookie", %{conn: conn, claims: claims} do
    user = AccountsFixtures.user_fixture(email: claims["email"])
    conn = conn |> get("/users/log_in") |> recycle()

    # A request with changed browser preferences still writes its snapshot of
    # the session. It can finish after a concurrent One Tap start request.
    started = start(conn)
    nonce = json_response(started, 200)["nonce"]
    passkey_options = conn |> put_req_cookie("user_timezone", "Europe/Madrid") |> post("/users/log_in/passkey/options")
    assert passkey_options.resp_cookies |> Map.keys() |> Enum.any?(&String.starts_with?(&1, "_tuist_key"))

    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)

    # The browser applies each response's cookies in arrival order.
    conn =
      started.resp_cookies
      |> Map.merge(passkey_options.resp_cookies)
      |> Enum.reduce(build_conn(), fn {name, %{value: value}}, conn -> put_req_cookie(conn, name, value) end)
      |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})

    assert redirected_to(conn) =~ "/#{user.account.name}"
    assert get_session(conn, :user_token)
  end

  test "parallel starts and independent completions survive either response arrival order", %{conn: conn, claims: claims} do
    for reverse? <- [false, true], concurrent_completions? <- [false, true] do
      # Both requests leave with the very same incoming browser cookies.
      first = start(conn)
      second = start(conn)
      nonce_a = json_response(first, 200)["nonce"]
      nonce_b = json_response(second, 200)["nonce"]
      responses = if reverse?, do: [second, first], else: [first, second]
      jar = Enum.reduce(responses, %{}, &apply_response_cookies/2)
      pending_jar = jar

      expect(Google, :verify_identity_token, fn "first-token", ^nonce_a -> {:ok, claims} end)
      expect(Google, :verify_identity_token, fn "second-token", ^nonce_b -> {:ok, claims} end)

      first_completion =
        jar |> browser_request() |> post("/auth/google/one-tap", %{credential: "first-token", nonce: nonce_a})

      assert redirected_to(first_completion) == "/users/choose-username"

      jar = apply_response_cookies(first_completion, jar)
      second_jar = if concurrent_completions?, do: pending_jar, else: jar

      second_completion =
        second_jar |> browser_request() |> post("/auth/google/one-tap", %{credential: "second-token", nonce: nonce_b})

      assert redirected_to(second_completion) == "/users/choose-username"

      jar = apply_response_cookies(second_completion, jar)

      for nonce <- [nonce_a, nonce_b] do
        replay = jar |> browser_request() |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})
        assert redirected_to(replay) == "/users/log_in"
      end
    end
  end

  test "retains outstanding legacy challenges alongside independent starts", %{conn: conn, claims: claims} do
    conn =
      conn
      |> Map.put(:secret_key_base, TuistWeb.Endpoint.config(:secret_key_base))
      |> put_resp_cookie("_tuist_google_one_tap", [%{nonce: "legacy", issued_at: System.system_time(:second)}],
        sign: true
      )
      |> recycle()
      |> start()

    nonce = json_response(conn, 200)["nonce"]
    refute Map.has_key?(conn.resp_cookies, "_tuist_google_one_tap")
    expect(Google, :verify_identity_token, fn "legacy-token", "legacy" -> {:ok, claims} end)
    expect(Google, :verify_identity_token, fn "new-token", ^nonce -> {:ok, claims} end)

    conn = conn |> recycle() |> post("/auth/google/one-tap", %{credential: "legacy-token", nonce: "legacy"})
    assert redirected_to(conn) == "/users/choose-username"
    conn = conn |> recycle() |> post("/auth/google/one-tap", %{credential: "new-token", nonce: nonce})
    assert redirected_to(conn) == "/users/choose-username"
  end

  test "bounds sequential pending cookies without evicting an active challenge", %{conn: conn} do
    conn = Enum.reduce(1..10, conn, fn _, conn -> conn |> recycle() |> start() end)
    assert length(challenges(conn)) == 10

    assert Enum.all?(conn.resp_cookies, fn {name, cookie} ->
             not String.starts_with?(name, "_tuist_google_one_tap_") or
               (byte_size(cookie.value) < 512 and cookie.max_age == 3600 and
                  cookie.path == "/auth/google/one-tap" and cookie.http_only)
           end)

    limited = conn |> recycle() |> start()
    assert response(limited, 204) == ""
    refute Enum.any?(limited.resp_cookies, fn {name, _} -> String.starts_with?(name, "_tuist_google_one_tap_") end)
  end

  test "rejects independent challenges without the signed browser cookie or after tampering", %{conn: conn} do
    started = start(conn)
    nonce = json_response(started, 200)["nonce"]
    name = "_tuist_google_one_tap_" <> nonce
    reject(Google, :verify_identity_token, 2)

    for request <- [conn, put_req_cookie(conn, name, started.resp_cookies[name].value <> "tampered")] do
      result = post(request, "/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})
      assert redirected_to(result) == "/users/log_in"
      refute get_session(result, :user_token)
    end
  end

  test "rejects expired and future-dated independent challenges", %{conn: conn} do
    nonce = String.duplicate("a", 43)
    name = "_tuist_google_one_tap_" <> nonce
    reject(Google, :verify_identity_token, 2)

    for issued_at <- [System.system_time(:second) - 3600, System.system_time(:second) + 3600] do
      result =
        conn
        |> Map.put(:secret_key_base, TuistWeb.Endpoint.config(:secret_key_base))
        |> put_resp_cookie(name, %{nonce: nonce, issued_at: issued_at}, sign: true)
        |> recycle()
        |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: nonce})

      assert redirected_to(result) == "/users/log_in"
      assert result.resp_cookies[name].max_age == 0
    end
  end

  test "rejects credentials without a challenge", %{conn: conn} do
    conn = post(conn, "/auth/google/one-tap", %{credential: "signed-token"})
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :user_token)
  end

  test "rejects an expired challenge", %{conn: conn} do
    conn =
      conn
      |> Map.put(:secret_key_base, TuistWeb.Endpoint.config(:secret_key_base))
      |> put_resp_cookie("_tuist_google_one_tap", [%{nonce: "old", issued_at: 0}], sign: true)
      |> recycle()
      |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: "old"})

    assert redirected_to(conn) == "/users/log_in"
    refute challenges(conn)
  end

  test "consumes the challenge on invalid credentials", %{conn: conn} do
    stub(Google, :verify_identity_token, fn _, _ -> {:error, :invalid_token} end)
    conn = conn |> start() |> complete("bad-token")
    assert redirected_to(conn) == "/users/log_in"
    refute challenges(conn)
    refute get_session(conn, :user_token)
  end

  test "does not issue a challenge or render the hook when disabled", %{conn: conn} do
    stub(Environment, :google_auth_enabled?, fn -> false end)
    assert conn |> post("/auth/google/one-tap/start") |> response(204) == ""
    refute render_component(&GoogleOneTap.prompt/1) =~ "google-one-tap"
  end

  test "does not render the hook or start sign-in for an authenticated user", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    assert conn |> log_in_user(user) |> post("/auth/google/one-tap/start") |> response(204) == ""
    refute render_component(&GoogleOneTap.prompt/1, current_user: user) =~ "google-one-tap"
  end

  test "does not render the hook without Google configuration" do
    stub(Environment, :google_oauth_configured?, fn -> false end)
    refute render_component(&GoogleOneTap.prompt/1) =~ "google-one-tap"
  end

  test "renders the hook with a protected credential form" do
    html = render_component(&GoogleOneTap.prompt/1)
    assert html =~ "/auth/google/one-tap/start"
    assert html =~ "_csrf_token"
    assert html =~ "credential"
  end

  test "filters credentials from request logs" do
    assert Phoenix.Logger.filter_values(%{"credential" => "sensitive"}) == %{"credential" => "[FILTERED]"}
  end

  test "authentication pages allow Google resources for subsequent live navigation", %{conn: conn} do
    for path <- ["/users/log_in", "/users/register", "/users/reset_password"] do
      response = get(conn, path)
      [policy] = get_resp_header(response, "content-security-policy")
      assert policy =~ "https://accounts.google.com/gsi/client"
      assert html_response(response, 200) =~ "id=\"google-one-tap\"" == (path != "/users/reset_password")
    end
  end

  test "only allows Google's resources when One Tap is enabled", %{conn: conn} do
    conn = TuistWeb.Router.google_one_tap_content_security_policy(conn, [])
    [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "https://accounts.google.com/gsi/client"
    assert policy =~ "https://accounts.google.com/gsi/"

    stub(Environment, :google_auth_enabled?, fn -> false end)
    conn = TuistWeb.Router.google_one_tap_content_security_policy(build_conn(), [])
    assert get_resp_header(conn, "content-security-policy") == []
  end

  defp complete(conn, credential) do
    nonce = json_response(conn, 200)["nonce"]
    conn |> recycle() |> post("/auth/google/one-tap", %{credential: credential, nonce: nonce})
  end

  defp start(conn), do: post(conn, "/auth/google/one-tap/start")

  defp apply_response_cookies(response, jar) do
    Enum.reduce(response.resp_cookies, jar, fn {name, options}, jar ->
      if options[:max_age] == 0, do: Map.delete(jar, name), else: Map.put(jar, name, options.value)
    end)
  end

  defp browser_request(jar) do
    Enum.reduce(jar, build_conn(), fn {name, value}, conn -> put_req_cookie(conn, name, value) end)
  end

  defp challenges(conn) do
    challenges =
      Enum.flat_map(conn.cookies, fn
        {"_tuist_google_one_tap", challenges} when is_list(challenges) -> challenges
        {"_tuist_google_one_tap_" <> _, %{nonce: _} = challenge} -> [challenge]
        _ -> []
      end)

    if challenges != [], do: challenges
  end

  defp enforce_csrf(conn), do: Plug.Conn.put_private(conn, :plug_skip_csrf_protection, false)

  defp signed_token(key, nonce, claims, overrides \\ %{}) do
    now = DateTime.to_unix(DateTime.utc_now())

    fields =
      claims
      |> Map.merge(%{
        "aud" => "tuist-client",
        "iss" => "https://accounts.google.com",
        "exp" => now + 3600,
        "iat" => now,
        "nonce" => nonce
      })
      |> Map.merge(overrides)

    key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "google-key"}, fields) |> JOSE.JWS.compact() |> elem(1)
  end

  defp use_public_key(public_key) do
    stub(KeyValueStore, :get, fn
      [Google, "public_keys"] -> [public_key]
      key -> Mimic.call_original(KeyValueStore, :get, [key])
    end)
  end
end
