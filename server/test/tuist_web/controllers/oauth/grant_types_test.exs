defmodule TuistWeb.Oauth.GrantTypesTest do
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

  describe "Tuist app client" do
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
      response = password_grant(@client_id, @client_secret, user)

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

    for response_type <- ["token", "code token", "code id_token", "id_token"] do
      test "rejects the #{response_type} response type", %{conn: conn} do
        response =
          conn
          |> get(~p"/oauth2/authorize", %{
            "response_type" => unquote(response_type),
            "client_id" => @client_id,
            "redirect_uri" => @redirect_uri,
            "state" => "app-state",
            "nonce" => "app-nonce",
            "code_challenge" => code_challenge(),
            "code_challenge_method" => "S256"
          })
          |> json_response(400)

        assert response["error"] == "unsupported_response_type"
        refute Map.has_key?(response, "access_token")
      end
    end
  end

  describe "dynamically registered clients" do
    test "only get the supported grant types", %{user: user} do
      registration = register(%{"grant_types" => ["password", "client_credentials", "authorization_code"]})

      assert registration["grant_types"] == ["authorization_code"]

      response = password_grant(registration["client_id"], registration["client_secret"], user)
      assert response["error"] == "unsupported_grant_type"
    end

    test "default to the supported grant types", %{user: user} do
      registration = register(%{})

      assert registration["grant_types"] == ["authorization_code", "refresh_token", "revoke"]

      response = password_grant(registration["client_id"], registration["client_secret"], user)
      assert response["error"] == "unsupported_grant_type"
    end
  end

  defp register(params) do
    build_conn()
    |> post(
      ~p"/oauth2/register",
      Map.merge(%{"client_name" => "Test client", "redirect_uris" => ["https://example.com/callback"]}, params)
    )
    |> json_response(201)
  end

  defp password_grant(client_id, client_secret, user) do
    build_conn()
    |> post(~p"/oauth2/token", %{
      "grant_type" => "password",
      "client_id" => client_id,
      "client_secret" => client_secret,
      "username" => user.email,
      "password" => AccountsFixtures.valid_user_password()
    })
    |> json_response(400)
  end

  defp code_challenge, do: :sha256 |> :crypto.hash(@code_verifier) |> Base.url_encode64(padding: false)

  defp authorize(conn) do
    %{"code" => code} =
      conn
      |> get(~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => @client_id,
        "redirect_uri" => @redirect_uri,
        "state" => "app-state",
        "code_challenge" => code_challenge(),
        "code_challenge_method" => "S256"
      })
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    code
  end
end
