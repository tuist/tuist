defmodule TuistWeb.GoogleOneTapTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.OAuth.Google
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.GoogleOneTap

  setup do
    stub(Environment, :google_auth_enabled?, fn -> true end)
    stub(Environment, :google_oauth_configured?, fn -> true end)
    stub(Environment, :google_oauth_client_id, fn -> "tuist-client" end)
    %{claims: %{"sub" => "google-user", "email" => "one-tap@gmail.com", "email_verified" => true}}
  end

  test "issues a fresh, uncacheable session challenge", %{conn: conn} do
    conn = post(conn, "/auth/google/one-tap/start")
    assert %{"client_id" => "tuist-client", "nonce" => nonce} = json_response(conn, 200)
    assert byte_size(nonce) >= 32
    assert %{nonce: ^nonce} = get_session(conn, :google_one_tap)
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "logs in an existing user using the verified Google identity", %{conn: conn, claims: claims} do
    user = AccountsFixtures.user_fixture(email: claims["email"])
    conn = start(conn)
    nonce = get_session(conn, :google_one_tap).nonce
    expect(Google, :verify_identity_token, fn "signed-token", ^nonce -> {:ok, claims} end)

    conn = conn |> recycle() |> post("/auth/google/one-tap", %{credential: "signed-token"})

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
    conn = conn |> start() |> recycle() |> post("/auth/google/one-tap", %{credential: "signed-token"})

    assert redirected_to(conn) == "/users/choose-username"
    assert %{"uid" => "google-user", "provider_organization_id" => "tuist.dev"} = get_session(conn, :pending_oauth_signup)
    refute get_session(conn, :google_one_tap)
  end

  test "falls back to standard sign-in before linking a third-party email", %{conn: conn, claims: claims} do
    claims = Map.put(claims, "email", "person@example.com")
    stub(Google, :verify_identity_token, fn _, _ -> {:ok, claims} end)
    conn = conn |> start() |> recycle() |> post("/auth/google/one-tap", %{credential: "signed-token"})
    assert redirected_to(conn) == "/users/auth/google"
    refute get_session(conn, :user_token)
  end

  test "does not require an authoritative email for an already-linked identity", %{conn: conn, claims: claims} do
    user = AccountsFixtures.user_fixture(email: "person@example.com")
    AccountsFixtures.oauth2_identity_fixture(user: user, id_in_provider: claims["sub"])
    stub(Google, :verify_identity_token, fn _, _ -> {:ok, Map.put(claims, "email", user.email)} end)
    conn = conn |> start() |> recycle() |> post("/auth/google/one-tap", %{credential: "signed-token"})
    assert redirected_to(conn) =~ "/#{user.account.name}"
  end

  test "rejects credentials without a challenge", %{conn: conn} do
    conn = post(conn, "/auth/google/one-tap", %{credential: "signed-token"})
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :user_token)
  end

  test "rejects an expired challenge", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{google_one_tap: %{nonce: "old", issued_at: 0}})
      |> post("/auth/google/one-tap", %{credential: "signed-token"})

    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :google_one_tap)
  end

  test "consumes the challenge on invalid credentials", %{conn: conn} do
    stub(Google, :verify_identity_token, fn _, _ -> {:error, :invalid_token} end)
    conn = conn |> start() |> recycle() |> post("/auth/google/one-tap", %{credential: "bad-token"})
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

  defp start(conn), do: post(conn, "/auth/google/one-tap/start")
end
