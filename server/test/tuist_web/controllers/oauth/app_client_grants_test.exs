defmodule TuistWeb.Oauth.AppClientGrantsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @client_id "00000000-0000-0000-0000-000000000001"
  @client_secret "configured-client-secret"
  @redirect_uri "tuist://oauth-callback"
  @code_verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  setup %{conn: conn} do
    stub(Environment, :oauth_client_id, fn -> @client_id end)
    stub(Environment, :oauth_client_secret, fn -> @client_secret end)

    user = AccountsFixtures.user_fixture(preload: [:account])
    %{conn: log_in_user(conn, user), user: user}
  end

  test "exchanges an authorization code with PKCE and refreshes the token", %{conn: conn, user: user} do
    code = authorize(conn)

    assert %{"access_token" => access_token, "refresh_token" => refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => @client_id,
               "redirect_uri" => @redirect_uri,
               "code" => code,
               "code_verifier" => @code_verifier
             })
             |> json_response(200)

    assert {:ok, claims} = Tuist.Guardian.decode_and_verify(access_token)
    assert claims["user_id"] == user.id

    assert %{"access_token" => refreshed_access_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => @client_id,
               "client_secret" => @client_secret,
               "refresh_token" => refresh_token
             })
             |> json_response(200)

    assert refreshed_access_token != access_token
  end

  test "rejects the password grant", %{user: user} do
    response =
      build_conn()
      |> post(~p"/oauth2/token", %{
        "grant_type" => "password",
        "client_id" => @client_id,
        "client_secret" => @client_secret,
        "username" => user.email,
        "password" => AccountsFixtures.valid_user_password()
      })
      |> json_response(400)

    assert response["error"] == "unsupported_grant_type"
    refute Map.has_key?(response, "access_token")
  end

  test "rejects the client credentials grant" do
    response =
      build_conn()
      |> post(~p"/oauth2/token", %{
        "grant_type" => "client_credentials",
        "client_id" => @client_id,
        "client_secret" => @client_secret
      })
      |> json_response(400)

    assert response["error"] == "unsupported_grant_type"
    refute Map.has_key?(response, "access_token")
  end

  test "rejects the implicit grant", %{conn: conn} do
    conn =
      get(conn, ~p"/oauth2/authorize", %{
        "response_type" => "token",
        "client_id" => @client_id,
        "redirect_uri" => @redirect_uri,
        "state" => "app-state"
      })

    fragment = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:fragment) |> URI.decode_query()

    assert fragment["error"] == "unsupported_grant_type"
    refute Map.has_key?(fragment, "access_token")
  end

  defp authorize(conn) do
    code_challenge = :sha256 |> :crypto.hash(@code_verifier) |> Base.url_encode64(padding: false)

    %{"code" => code} =
      conn
      |> get(~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => @client_id,
        "redirect_uri" => @redirect_uri,
        "state" => "app-state",
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      })
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    code
  end
end
