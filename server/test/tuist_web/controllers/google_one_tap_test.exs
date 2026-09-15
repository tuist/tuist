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
    stub(Environment, :google_auth_enabled?, fn -> true end)
    stub(Environment, :google_oauth_configured?, fn -> true end)
    stub(Environment, :google_oauth_client_id, fn -> "tuist-client" end)
    %{claims: %{"sub" => "google-user", "email" => "one-tap@gmail.com", "email_verified" => true}}
  end

  test "issues a fresh, uncacheable session challenge", %{conn: conn} do
    conn = post(conn, "/auth/google/one-tap/start")
    assert %{"client_id" => "tuist-client", "nonce" => nonce, "csrf_token" => csrf_token} = json_response(conn, 200)
    assert byte_size(nonce) >= 32
    assert is_binary(csrf_token)
    assert [%{nonce: ^nonce}] = get_session(conn, :google_one_tap)
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

  test "rejects start requests that are not provably same-origin", %{conn: conn} do
    for headers <- [
          [],
          [{"origin", "https://evil.example"}],
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
    refute get_session(conn, :google_one_tap)
    assert {:ok, identity} = Tuist.Accounts.get_oauth2_identity(:google, claims["sub"])
    assert identity.user.id == user.id
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
    refute get_session(conn, :google_one_tap)
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
    assert [%{nonce: ^nonce_b}, %{nonce: ^nonce_a}] = get_session(conn, :google_one_tap)

    conn =
      conn
      |> recycle()
      |> post("/auth/google/one-tap", %{credential: signed_token(key, nonce_b, signup_claims), nonce: nonce_b})

    assert redirected_to(conn) == "/users/choose-username"
    assert [%{nonce: ^nonce_a}] = get_session(conn, :google_one_tap)
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
    assert [%{nonce: ^nonce_b}] = get_session(failed, :google_one_tap)

    completion =
      failed
      |> recycle()
      |> post("/auth/google/one-tap", %{credential: signed_token(key, nonce_b, claims), nonce: nonce_b})

    assert redirected_to(completion) =~ "/#{user.account.name}"
    refute get_session(completion, :google_one_tap)
  end

  test "rejects credentials without a challenge", %{conn: conn} do
    conn = post(conn, "/auth/google/one-tap", %{credential: "signed-token"})
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :user_token)
  end

  test "rejects an expired challenge", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{google_one_tap: [%{nonce: "old", issued_at: 0}]})
      |> post("/auth/google/one-tap", %{credential: "signed-token", nonce: "old"})

    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :google_one_tap)
  end

  test "consumes the challenge on invalid credentials", %{conn: conn} do
    stub(Google, :verify_identity_token, fn _, _ -> {:error, :invalid_token} end)
    conn = conn |> start() |> complete("bad-token")
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :google_one_tap)
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
