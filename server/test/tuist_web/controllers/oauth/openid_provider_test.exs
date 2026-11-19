defmodule TuistWeb.Oauth.OpenidProviderTest do
  @moduledoc """
  The contract the Luft server (`luft.work`) relies on, end to end: it
  discovers the provider, signs a person in with the authorization code flow
  (confidential client and PKCE), verifies the ID token against the published
  keys, reads userinfo, and lists and creates the person's organizations
  through the Tuist API with the access token, which can do only what its
  scopes grant.
  """
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @client_id "0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37"
  @client_secret "luft-server-secret"
  @redirect_uri "https://luft.work/auth/callback"
  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "without a signing key" do
    test "is no OpenID Provider", %{conn: conn} do
      stub(Environment, :oidc_signing_key, fn -> nil end)

      assert build_conn() |> get("/.well-known/openid-configuration") |> json_response(404)
      assert build_conn() |> get("/oauth2/jwks") |> json_response(404)

      # Nor is the Luft server's client registered.
      conn = get(conn, "/oauth2/authorize", authorize_params())
      refute conn.status == 302 and redirected_to(conn) =~ "code="
    end
  end

  describe "as the Luft server's OpenID Provider" do
    setup do
      key = {:rsa, 2048} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_pem() |> elem(1)
      stub(Environment, :oidc_signing_key, fn -> key end)
      stub(Environment, :luft_server_oauth_client_id, fn -> @client_id end)
      stub(Environment, :luft_server_oauth_client_secret, fn -> @client_secret end)
      stub(Environment, :luft_server_oauth_redirect_uris, fn -> [@redirect_uri] end)
      :ok
    end

    test "signs in, verifies the ID token, and manages organizations", %{conn: conn, user: user} do
      organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])
      _foreign = AccountsFixtures.organization_fixture(preload: [:account])

      metadata = build_conn() |> get("/.well-known/openid-configuration") |> json_response(200)
      issuer = metadata["issuer"]
      assert metadata["prompt_values_supported"] == ["create"]
      assert metadata["code_challenge_methods_supported"] == ["S256"]

      %{"keys" => [jwk]} = build_conn() |> get(URI.parse(metadata["jwks_uri"]).path) |> json_response(200)
      refute Map.has_key?(jwk, "d"), "the JWK Set must only carry the public key"

      tokens = sign_in(conn, authorize_params())

      {true, %JOSE.JWT{fields: claims}, %JOSE.JWS{alg: {_, :RS256}, fields: %{"kid" => kid}}} =
        jwk |> JOSE.JWK.from_map() |> JOSE.JWT.verify_strict(["RS256"], tokens["id_token"])

      assert kid == jwk["kid"]

      assert %{
               "iss" => ^issuer,
               "aud" => @client_id,
               "sub" => sub,
               "nonce" => "nonce-1",
               "email" => email,
               "preferred_username" => handle
             } = claims

      assert sub == to_string(user.id)
      assert email == user.email
      assert handle == user.account.name
      assert claims["exp"] > System.system_time(:second)

      bearer = fn conn -> put_req_header(conn, "authorization", "Bearer " <> tokens["access_token"]) end

      assert %{"sub" => ^sub, "email" => ^email} =
               build_conn() |> bearer.() |> get(URI.parse(metadata["userinfo_endpoint"]).path) |> json_response(200)

      assert %{"organizations" => [%{"name" => listed}]} =
               build_conn() |> bearer.() |> get("/api/organizations") |> json_response(200)

      assert listed == organization.account.name

      assert %{"name" => "luft-created"} =
               build_conn()
               |> bearer.()
               |> put_req_header("content-type", "application/json")
               |> post("/api/organizations", JSON.encode!(%{name: "luft-created"}))
               |> json_response(200)

      assert [_, _] = Accounts.get_user_organization_accounts(user)

      # Not a first-party app: endpoints only the Tuist and Luft apps may use
      # stay closed to it.
      assert build_conn() |> bearer.() |> get("/api/me/feature-flags") |> json_response(403)
    end

    test "creates organizations only with account:organizations:write", %{conn: conn, user: user} do
      tokens = sign_in(conn, authorize_params(%{"scope" => "openid profile email"}))

      assert build_conn()
             |> put_req_header("authorization", "Bearer " <> tokens["access_token"])
             |> put_req_header("content-type", "application/json")
             |> post("/api/organizations", JSON.encode!(%{name: "luft-unscoped"}))
             |> json_response(403)

      assert Accounts.get_user_organization_accounts(user) == []
    end

    test "refuses a wrong secret, a missing PKCE verifier, and scopes it was not given", %{conn: conn} do
      exchange = fn secret, extra ->
        %{"code" => code} = conn |> get("/oauth2/authorize", authorize_params()) |> redirect_query()

        build_conn()
        |> put_req_header("authorization", "Basic " <> Base.encode64("#{@client_id}:#{secret}"))
        |> post(
          "/oauth2/token",
          Map.merge(%{"grant_type" => "authorization_code", "redirect_uri" => @redirect_uri, "code" => code}, extra)
        )
      end

      assert exchange.("wrong", %{"code_verifier" => @verifier}).status == 401
      assert exchange.(@client_secret, %{}).status == 400

      assert %{"error" => "invalid_scope"} =
               conn |> get("/oauth2/authorize", authorize_params(%{"scope" => "openid mcp"})) |> redirect_query()

      # Tokens without a scope get Tuist's default user scopes, so an empty
      # request must not slip through as "nothing beyond what it may have".
      for params <- [authorize_params(%{"scope" => ""}), Map.delete(authorize_params(), "scope")] do
        assert %{"error" => "invalid_scope"} = conn |> get("/oauth2/authorize", params) |> redirect_query()
      end
    end

    test "refreshing with a blank scope grants no scopes", %{conn: conn} do
      tokens = sign_in(conn, authorize_params(%{"scope" => "openid"}))

      refreshed =
        build_conn()
        |> put_req_header("authorization", "Basic " <> Base.encode64("#{@client_id}:#{@client_secret}"))
        |> post("/oauth2/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => tokens["refresh_token"],
          "scope" => ""
        })
        |> json_response(200)

      # Tuist's default user scopes would read and write every project.
      assert %JOSE.JWT{fields: %{"scopes" => []}} = JOSE.JWT.peek_payload(refreshed["access_token"])
    end

    test "prompt=create sends a signed-out person to sign up, then back to the authorization" do
      conn = get(build_conn(), "/oauth2/authorize", authorize_params(%{"prompt" => "create"}))

      assert redirected_to(conn) == "/users/register"
      assert get_session(conn, :user_return_to) =~ "/oauth2/authorize?"
    end

    test "userinfo refuses tokens without the openid scope" do
      assert build_conn()
             |> put_req_header("authorization", "Bearer not-a-token")
             |> get("/oauth2/userinfo")
             |> json_response(401)
    end
  end

  defp authorize_params(overrides \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => @client_id,
        "redirect_uri" => @redirect_uri,
        "scope" => "openid profile email account:organizations:write",
        "state" => "state-1",
        "nonce" => "nonce-1",
        "code_challenge" => :sha256 |> :crypto.hash(@verifier) |> Base.url_encode64(padding: false),
        "code_challenge_method" => "S256"
      },
      overrides
    )
  end

  defp sign_in(conn, params) do
    %{"code" => code, "state" => "state-1"} = conn |> get("/oauth2/authorize", params) |> redirect_query()

    build_conn()
    |> put_req_header("authorization", "Basic " <> Base.encode64("#{@client_id}:#{@client_secret}"))
    |> post("/oauth2/token", %{
      "grant_type" => "authorization_code",
      "redirect_uri" => @redirect_uri,
      "code" => code,
      "code_verifier" => @verifier
    })
    |> json_response(200)
  end

  defp redirect_query(conn) do
    location = redirected_to(conn)
    assert String.starts_with?(location, @redirect_uri)
    location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end
end
