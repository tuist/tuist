defmodule TuistWeb.Oauth.GrantTypesTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo
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

    test "a password reset ends grants issued before it", %{conn: conn, user: user} do
      code = authorize(conn)

      %{"access_token" => access_token, "refresh_token" => refresh_token} =
        build_conn()
        |> post(~p"/oauth2/token", %{
          "grant_type" => "authorization_code",
          "client_id" => @client_id,
          "redirect_uri" => @redirect_uri,
          "code" => code,
          "code_verifier" => @code_verifier
        })
        |> json_response(200)

      {reset_token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)
      {:ok, _} = Accounts.reset_user_password(reset_token, %{password: "new valid password"})

      refute Tuist.Authentication.authenticated_subject(access_token)

      response =
        build_conn()
        |> post(~p"/oauth2/token", %{
          "grant_type" => "refresh_token",
          "client_id" => @client_id,
          "client_secret" => @client_secret,
          "refresh_token" => refresh_token
        })
        |> json_response(400)

      assert response["error"] == "invalid_grant"
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

  describe "request_uri" do
    setup do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])
      {:ok, port} = :inet.port(listener)
      test_pid = self()
      spawn_link(fn -> serve_request_uri_probe(listener, test_pid) end)
      on_exit(fn -> :gen_tcp.close(listener) end)

      %{request_uri: "http://127.0.0.1:#{port}/probe"}
    end

    test "is not fetched for the client credentials grant", %{request_uri: request_uri} do
      response =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/oauth2/token", JSON.encode!(%{"grant_type" => "client_credentials", "request_uri" => request_uri}))
        |> json_response(400)

      refute_received {:request_uri_probe, _request_line}
      assert response["error"] == "request_uri_not_supported"
    end

    test "is not fetched for the refresh token grant", %{request_uri: request_uri} do
      response =
        build_conn()
        |> post("/oauth2/token?" <> URI.encode_query(%{"request_uri" => request_uri}), %{
          "grant_type" => "refresh_token",
          "refresh_token" => "unknown"
        })
        |> json_response(400)

      refute_received {:request_uri_probe, _request_line}
      assert response["error"] == "request_uri_not_supported"
    end

    test "is not fetched for an authorization request", %{conn: conn, request_uri: request_uri} do
      response =
        conn
        |> get(~p"/oauth2/authorize", %{
          "response_type" => "code",
          "client_id" => @client_id,
          "request_uri" => request_uri
        })
        |> json_response(400)

      refute_received {:request_uri_probe, _request_line}
      assert response["error"] == "request_uri_not_supported"
    end
  end

  defp serve_request_uri_probe(listener, test_pid) do
    with {:ok, socket} <- :gen_tcp.accept(listener),
         {:ok, request} <- :gen_tcp.recv(socket, 0, 5_000) do
      [request_line | _] = String.split(request, "\r\n")
      send(test_pid, {:request_uri_probe, request_line})
      :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 9\r\nconnection: close\r\n\r\nnot-a-jwt")
      :gen_tcp.close(socket)
      serve_request_uri_probe(listener, test_pid)
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
