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
  use TuistWeb.ConnCase, async: true

  alias Boruta.Ecto.Token
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

  test "rejects a refresh token that has already been used", %{conn: conn} do
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

    refresh = fn ->
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "client_id" => client_id,
        "refresh_token" => refresh_token
      })
    end

    assert %{"access_token" => _} = json_response(refresh.(), 200)
    assert %{"error" => "invalid_grant"} = json_response(refresh.(), 400)
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
