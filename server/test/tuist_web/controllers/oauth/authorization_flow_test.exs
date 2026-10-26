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
    conn =
      get(conn, ~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => @redirect_uri,
        "scope" => "mcp",
        "state" => "claude-state"
      })

    %{"code" => code} =
      conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    code
  end
end
