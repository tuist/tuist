defmodule TuistWeb.Oauth.AuthorizationFlowTest do
  @moduledoc """
  End-to-end coverage of the OAuth grants MCP clients use against
  `/mcp`: dynamic registration, the authorization code exchange, and the
  refresh that keeps a client connected without another browser round trip.

  The refresh leg is the one worth guarding. Atlas ran the same Boruta
  setup and its refresh grant was broken from the day it shipped, unnoticed
  for four months, because the only OAuth test there stopped at the code
  exchange.
  """
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Boruta.Ecto.AccessTokens
  alias Boruta.Ecto.Admin
  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Codes
  alias Boruta.Ecto.Token
  alias Tuist.Authentication.RefreshReplays
  alias Tuist.Environment
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @redirect_uri "https://claude.ai/api/mcp/auth_callback"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{conn: log_in_user(conn, user), user: user}
  end

  test "registers a client, exchanges a code, and refreshes the token", %{conn: conn, user: user} do
    client_id = register_client(conn)
    code = authorize(conn, client_id)

    token_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => @redirect_uri,
        "code" => code
      })

    assert %{"access_token" => access_token, "refresh_token" => refresh_token} =
             json_response(token_conn, 200)

    assert {:ok, claims} = Tuist.Guardian.decode_and_verify(access_token)
    assert claims["user_id"] == user.id
    assert claims["scopes"] == ["mcp"]

    refresh_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "client_id" => client_id,
        "refresh_token" => refresh_token
      })

    assert %{"access_token" => refreshed_access_token, "refresh_token" => refreshed_refresh_token} =
             json_response(refresh_conn, 200)

    assert refreshed_access_token != access_token
    assert refreshed_refresh_token != refresh_token

    assert {:ok, refreshed_claims} = Tuist.Guardian.decode_and_verify(refreshed_access_token)
    assert refreshed_claims["user_id"] == user.id
    assert refreshed_claims["scopes"] == ["mcp"]

    # The refreshed token records the JWT it replaced. `previous_token` was
    # `varchar(255)` until it was widened to `text`, which a JWT overflows.
    assert %Token{previous_token: ^access_token} = Repo.get_by!(Token, value: refreshed_access_token)

    # The rotated refresh token has to be redeemable, otherwise a client gets
    # exactly one refresh out of a sign-in.
    assert %{"access_token" => third_access_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => client_id,
               "refresh_token" => refreshed_refresh_token
             })
             |> json_response(200)

    refute third_access_token in [access_token, refreshed_access_token]
  end

  test "requires the sign-in the user's SSO-enforcing organization requires", %{conn: conn, user: user} do
    client_id = register_client(conn)
    organization = AccountsFixtures.organization_fixture()
    :ok = Tuist.Accounts.add_user_to_organization(user, organization, role: :user)

    organization
    |> Ecto.Changeset.change(sso_enforced: true, sso_provider: :google, sso_organization_id: "oauthflow-example.com")
    |> Repo.update!()

    password_conn = get(conn, ~p"/oauth2/authorize", authorize_params(client_id))

    assert redirected_to(password_conn) == "/users/auth/google"
    assert "/oauth2/authorize?" <> _ = get_session(password_conn, :user_return_to)

    google_token =
      Tuist.Accounts.generate_user_session_token(user, %{
        auth_method: :google,
        provider_organization_id: "oauthflow-example.com"
      })

    assert build_conn() |> init_test_session(%{}) |> put_session(:user_token, google_token) |> authorize(client_id)
  end

  describe "client jwks_uri" do
    # Registration is anonymous and Boruta fetches `jwks_uri` with a plain
    # Finch GET, so accepting it would let anyone make the server request an
    # arbitrary internal address.
    test "registration rejects it without fetching it, whether or not the rest of the metadata is valid" do
      port = start_loopback_fixture()
      jwks_uri = "http://127.0.0.1:#{port}/probe"

      for redirect_uris <- [["not a uri"], [@redirect_uri]] do
        conn =
          post(build_conn(), ~p"/oauth2/register", %{
            "client_name" => "Probe",
            "redirect_uris" => redirect_uris,
            "grant_types" => ["authorization_code"],
            "response_types" => ["code"],
            "jwks_uri" => jwks_uri
          })

        refute_received {:loopback_fixture_request, _}

        assert %{"error" => "invalid_client_metadata", "error_description" => "jwks_uri is not supported." <> _} =
                 json_response(conn, 400)
      end

      refute Repo.exists?(from(client in Client, where: client.name == "Probe"))
    end

    test "token requests never fetch one stored on an existing client" do
      port = start_loopback_fixture()
      public_jwk = {:rsa, 2048} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_public_map() |> elem(1)

      {:ok, client} =
        Admin.create_client(%{
          name: "Stored jwks_uri",
          confidential: true,
          redirect_uris: [@redirect_uri],
          supported_grant_types: ["authorization_code"],
          token_endpoint_auth_methods: ["private_key_jwt"],
          token_endpoint_jwt_auth_alg: "RS256",
          jwk: Map.put(public_jwk, "alg", "RS256"),
          jwks_uri: "http://127.0.0.1:#{port}/probe"
        })

      # Signed by a key the client doesn't have, so Boruta's verification
      # fails and it falls back to refreshing the client's key from jwks_uri.
      other_key = JOSE.JWK.generate_key({:rsa, 2048})

      {_, assertion} =
        other_key
        |> JOSE.JWT.sign(%{"alg" => "RS256"}, %{
          "iss" => client.id,
          "sub" => client.id,
          "aud" => Boruta.Config.issuer(),
          "exp" => System.system_time(:second) + 60
        })
        |> JOSE.JWS.compact()

      token_conn =
        post(build_conn(), ~p"/oauth2/token", %{
          "grant_type" => "authorization_code",
          "client_id" => client.id,
          "redirect_uri" => @redirect_uri,
          "code" => "unused",
          "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          "client_assertion" => assertion
        })

      assert %{"error" => "invalid_client"} = json_response(token_conn, 401)
      refute_received {:loopback_fixture_request, _}
    end
  end

  describe "refreshing with SSO enforcement" do
    test "tokens authorized through the organization's SSO keep its proof and keep refreshing", %{user: user} do
      organization = sso_member_of(user)
      client_id = register_client(build_conn())
      sso_conn = sso_session_conn(user, organization)

      %{"access_token" => access_token, "refresh_token" => refresh_token} =
        exchange_code(client_id, authorize(sso_conn, client_id))

      assert {:ok, %{"sso" => %{"provider" => "google", "provider_organization_id" => "oauthflow-example.com"}}} =
               Tuist.Guardian.decode_and_verify(access_token)

      assert %{"access_token" => refreshed_access_token, "refresh_token" => refreshed_refresh_token} =
               client_id |> refresh_conn(refresh_token) |> json_response(200)

      # The proof carries over to the rotated pair, so later refreshes pass too.
      assert {:ok, %{"sso" => %{"provider_organization_id" => "oauthflow-example.com"}}} =
               Tuist.Guardian.decode_and_verify(refreshed_access_token)

      assert %{"access_token" => _} = client_id |> refresh_conn(refreshed_refresh_token) |> json_response(200)
    end

    test "tokens without SSO proof keep refreshing for users no organization enforces it for", %{
      conn: conn,
      user: user
    } do
      tap(
        AccountsFixtures.organization_fixture(),
        &(:ok = Tuist.Accounts.add_user_to_organization(user, &1, role: :user))
      )

      client_id = register_client(conn)
      %{"refresh_token" => refresh_token} = exchange_code(client_id, authorize(conn, client_id))

      assert %{"access_token" => _} = client_id |> refresh_conn(refresh_token) |> json_response(200)
    end

    test "tokens issued without SSO proof take the identity the user linked through the provider", %{
      conn: conn,
      user: user
    } do
      client_id = register_client(conn)
      # Authorized from a password session, as every token issued before
      # tokens carried SSO proof was.
      %{"refresh_token" => refresh_token} = exchange_code(client_id, authorize(conn, client_id))
      organization = sso_member_of(user)

      AccountsFixtures.oauth2_identity_fixture(
        user: user,
        provider: :google,
        provider_organization_id: "oauthflow-example.com"
      )

      assert %{"access_token" => access_token, "refresh_token" => refreshed_refresh_token} =
               client_id |> refresh_conn(refresh_token) |> json_response(200)

      for token <- [access_token, refreshed_refresh_token] do
        assert {:ok, %{"sso" => %{"provider" => "google", "organization_id" => organization_id}} = claims} =
                 Tuist.Guardian.decode_and_verify(token)

        assert organization_id == organization.id
        refute Map.has_key?(claims, "sso_grace_until")
      end

      assert %{"access_token" => _} = client_id |> refresh_conn(refreshed_refresh_token) |> json_response(200)
    end

    test "tokens issued without SSO proof refresh for a grace period that never extends, then stop", %{
      conn: conn,
      user: user
    } do
      client_id = register_client(conn)
      %{"refresh_token" => refresh_token} = exchange_code(client_id, authorize(conn, client_id))
      sso_member_of(user)
      now = DateTime.utc_now()

      assert %{"access_token" => access_token, "refresh_token" => first_refresh_token} =
               client_id |> refresh_conn(refresh_token) |> json_response(200)

      assert {:ok, %{"sso_grace_until" => grace_until} = claims} = Tuist.Guardian.decode_and_verify(access_token)
      refute Map.has_key?(claims, "sso")
      assert_in_delta grace_until, DateTime.to_unix(now) + 28 * 24 * 60 * 60, 60

      assert %{"access_token" => second_access_token, "refresh_token" => second_refresh_token} =
               client_id |> refresh_conn(first_refresh_token) |> json_response(200)

      assert {:ok, %{"sso_grace_until" => ^grace_until}} = Tuist.Guardian.decode_and_verify(second_access_token)

      stub(Tuist.Time, :utc_now, fn -> DateTime.add(now, 29, :day) end)

      assert %{"error" => "invalid_grant", "error_description" => "Your organization requires single sign-on." <> _} =
               client_id |> refresh_conn(second_refresh_token) |> json_response(400)

      # The refused token is not spent: signing in through the provider
      # links the identity that lets it refresh again.
      AccountsFixtures.oauth2_identity_fixture(
        user: user,
        provider: :google,
        provider_organization_id: "oauthflow-example.com"
      )

      assert %{"access_token" => _} = client_id |> refresh_conn(second_refresh_token) |> json_response(200)
    end

    test "a refresh smuggled in an unsigned request object does not skip the SSO check", %{conn: conn, user: user} do
      client_id = register_client(conn)
      %{"refresh_token" => refresh_token} = exchange_code(client_id, authorize(conn, client_id))
      sso_member_of(user)
      stub(Tuist.Time, :utc_now, fn -> DateTime.add(DateTime.utc_now(), 29, :day) end)

      unsigned_request =
        Enum.map_join(
          [%{"alg" => "none"}, %{"grant_type" => "refresh_token", "refresh_token" => refresh_token}],
          ".",
          &(&1 |> JSON.encode!() |> Base.url_encode64(padding: false))
        ) <> "."

      response =
        build_conn()
        |> post(~p"/oauth2/token", %{"client_id" => client_id, "request" => unsigned_request})
        |> json_response(400)

      refute Map.has_key?(response, "access_token")
    end

    test "tokens whose SSO proof no longer matches the organization drop it for a grace period", %{user: user} do
      organization = sso_member_of(user)
      client_id = register_client(build_conn())

      %{"refresh_token" => refresh_token} =
        exchange_code(client_id, authorize(sso_session_conn(user, organization), client_id))

      organization |> Ecto.Changeset.change(sso_organization_id: "other.oauthflow-example.com") |> Repo.update!()

      assert %{"access_token" => access_token} = client_id |> refresh_conn(refresh_token) |> json_response(200)
      assert {:ok, claims} = Tuist.Guardian.decode_and_verify(access_token)
      refute Map.has_key?(claims, "sso")
      assert is_integer(claims["sso_grace_until"])
    end
  end

  test "rejects a code revoked in the database after an earlier lookup", %{conn: conn} do
    client_id = register_client(conn)
    code = authorize(conn, client_id)
    assert Codes.get_by(value: code).revoked_at == nil

    Token
    |> Repo.get_by!(value: code)
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now())
    |> Repo.update!()

    assert %{"error" => "invalid_grant"} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => client_id,
               "redirect_uri" => @redirect_uri,
               "code" => code
             })
             |> json_response(400)
  end

  test "rejects a refresh token revoked in the database after an earlier lookup", %{conn: conn} do
    client_id = register_client(conn)
    code = authorize(conn, client_id)

    assert %{"refresh_token" => refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => client_id,
               "redirect_uri" => @redirect_uri,
               "code" => code
             })
             |> json_response(200)

    assert AccessTokens.get_by(refresh_token: refresh_token).refresh_token_revoked_at == nil

    Token
    |> Repo.get_by!(refresh_token: refresh_token)
    |> Ecto.Changeset.change(refresh_token_revoked_at: DateTime.utc_now())
    |> Repo.update!()

    assert %{"error" => "invalid_grant"} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => client_id,
               "refresh_token" => refresh_token
             })
             |> json_response(400)
  end

  test "replays a used refresh token's response within the window and rejects it after", %{conn: conn} do
    client_id = register_client(conn)
    other_client_id = register_client(conn)
    code = authorize(conn, client_id)

    assert %{"refresh_token" => refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => client_id,
               "redirect_uri" => @redirect_uri,
               "code" => code
             })
             |> json_response(200)

    refresh = fn client_id ->
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "client_id" => client_id,
        "refresh_token" => refresh_token
      })
    end

    first_conn = refresh.(client_id)
    assert %{"access_token" => _, "refresh_token" => rotated_refresh_token} = first = json_response(first_conn, 200)

    # A client whose response was lost gets the same tokens back, and they work.
    replay_conn = refresh.(client_id)
    assert json_response(replay_conn, 200) == first
    assert get_resp_header(replay_conn, "cache-control") == ["no-store"]

    # Another client presenting the token gets nothing.
    assert %{"error" => "invalid_grant"} = json_response(refresh.(other_client_id), 400)

    assert %{"access_token" => _} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => client_id,
               "refresh_token" => rotated_refresh_token
             })
             |> json_response(200)

    after_window = DateTime.add(DateTime.utc_now(), RefreshReplays.window_seconds() + 1, :second)
    stub(Tuist.Time, :utc_now, fn -> after_window end)

    assert %{"error" => "invalid_grant"} = json_response(refresh.(client_id), 400)
  end

  test "concurrent refreshes of the same token return one pair", %{conn: conn} do
    client_id = register_client(conn)
    code = authorize(conn, client_id)

    assert %{"refresh_token" => refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => client_id,
               "redirect_uri" => @redirect_uri,
               "code" => code
             })
             |> json_response(200)

    responses =
      1..4
      |> Enum.map(fn _ ->
        Task.async(fn ->
          build_conn()
          |> post(~p"/oauth2/token", %{
            "grant_type" => "refresh_token",
            "client_id" => client_id,
            "refresh_token" => refresh_token
          })
          |> json_response(200)
        end)
      end)
      |> Task.await_many()

    assert [%{"access_token" => _}] = Enum.uniq(responses)

    # The code exchange minted one access token and the refreshes one more.
    assert Repo.aggregate(
             from(token in Token, where: token.client_id == ^client_id and token.type == "access_token"),
             :count
           ) == 2
  end

  test "the Tuist app client refreshes without its client secret", %{conn: conn} do
    client_id = "00000000-0000-0000-0000-000000000001"
    verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    stub(Environment, :oauth_client_id, fn -> client_id end)
    stub(Environment, :oauth_client_secret, fn -> "configured-client-secret" end)

    %{"code" => code} =
      conn
      |> get(~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => "tuist://oauth-callback",
        "state" => "app-state",
        "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false),
        "code_challenge_method" => "S256"
      })
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert %{"refresh_token" => refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => client_id,
               "redirect_uri" => "tuist://oauth-callback",
               "code" => code,
               "code_verifier" => verifier
             })
             |> json_response(200)

    assert %{"access_token" => _, "refresh_token" => _} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => client_id,
               "refresh_token" => refresh_token
             })
             |> json_response(200)
  end

  test "the Tuist app client can't refresh another client's token or widen its scopes", %{conn: conn} do
    app_client_id = "00000000-0000-0000-0000-000000000001"
    verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    stub(Environment, :oauth_client_secret, fn -> "configured-client-secret" end)

    mcp_client_id = register_client(conn)

    assert %{"refresh_token" => mcp_refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => mcp_client_id,
               "redirect_uri" => @redirect_uri,
               "code" => authorize(conn, mcp_client_id)
             })
             |> json_response(200)

    assert %{"error" => "invalid_grant"} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => app_client_id,
               "refresh_token" => mcp_refresh_token
             })
             |> json_response(400)

    %{"code" => code} =
      conn
      |> get(~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => app_client_id,
        "redirect_uri" => "tuist://oauth-callback",
        "scope" => "mcp",
        "state" => "app-state",
        "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false),
        "code_challenge_method" => "S256"
      })
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert %{"refresh_token" => refresh_token} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "authorization_code",
               "client_id" => app_client_id,
               "redirect_uri" => "tuist://oauth-callback",
               "code" => code,
               "code_verifier" => verifier
             })
             |> json_response(200)

    assert %{"error" => "invalid_scope"} =
             build_conn()
             |> post(~p"/oauth2/token", %{
               "grant_type" => "refresh_token",
               "client_id" => app_client_id,
               "refresh_token" => refresh_token,
               "scope" => "project:admin:write project:cache:write"
             })
             |> json_response(400)
  end

  defp sso_member_of(user) do
    organization = AccountsFixtures.organization_fixture()
    :ok = Tuist.Accounts.add_user_to_organization(user, organization, role: :user)

    # Enabling enforcement through `Accounts` also requires a verified login
    # email domain, which is not what these tests are about.
    organization
    |> Ecto.Changeset.change(sso_enforced: true, sso_provider: :google, sso_organization_id: "oauthflow-example.com")
    |> Repo.update!()
  end

  defp sso_session_conn(user, organization) do
    token =
      Tuist.Accounts.generate_user_session_token(user, %{
        auth_method: organization.sso_provider,
        provider_organization_id: organization.sso_organization_id
      })

    build_conn() |> init_test_session(%{}) |> put_session(:user_token, token)
  end

  defp exchange_code(client_id, code) do
    build_conn()
    |> post(~p"/oauth2/token", %{
      "grant_type" => "authorization_code",
      "client_id" => client_id,
      "redirect_uri" => @redirect_uri,
      "code" => code
    })
    |> json_response(200)
  end

  defp refresh_conn(client_id, refresh_token) do
    post(build_conn(), ~p"/oauth2/token", %{
      "grant_type" => "refresh_token",
      "client_id" => client_id,
      "refresh_token" => refresh_token
    })
  end

  # A loopback HTTP server that reports every request it receives to the test
  # process and answers 404. Requests are synchronous, so a fetch made while
  # handling a call has been reported by the time the call returns.
  defp start_loopback_fixture do
    test_pid = self()
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    spawn_link(fn -> serve_loopback_fixture(socket, test_pid) end)
    port
  end

  defp serve_loopback_fixture(socket, test_pid) do
    with {:ok, client} <- :gen_tcp.accept(socket) do
      # Report the connection even if it never sends a full request.
      request =
        case :gen_tcp.recv(client, 0, 5_000) do
          {:ok, request} -> request
          {:error, reason} -> reason
        end

      send(test_pid, {:loopback_fixture_request, request})
      :gen_tcp.send(client, "HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
      :gen_tcp.close(client)
      serve_loopback_fixture(socket, test_pid)
    end
  end

  defp register_client(conn) do
    assert %{"client_id" => client_id} =
             conn
             |> post(~p"/oauth2/register", %{
               "client_name" => "Claude Code",
               "redirect_uris" => [@redirect_uri],
               "grant_types" => ["authorization_code", "refresh_token"],
               "response_types" => ["code"],
               "token_endpoint_auth_method" => "none"
             })
             |> json_response(201)

    client_id
  end

  defp authorize(conn, client_id) do
    conn = get(conn, ~p"/oauth2/authorize", authorize_params(client_id))

    %{"code" => code} =
      conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    code
  end

  defp authorize_params(client_id) do
    %{
      "response_type" => "code",
      "client_id" => client_id,
      "redirect_uri" => @redirect_uri,
      "scope" => "mcp",
      "state" => "claude-state"
    }
  end
end
