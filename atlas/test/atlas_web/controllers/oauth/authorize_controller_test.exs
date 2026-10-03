defmodule AtlasWeb.Oauth.AuthorizeControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Guardian
  alias Atlas.Repo
  alias Boruta.Ecto.Scope
  alias Boruta.Ecto.Scopes
  alias Boruta.Ecto.Token

  setup do
    Scopes.invalidate(:public)
    :ok
  end

  test "mcp is registered as a public OAuth scope" do
    assert %Scope{public: true, label: "Atlas MCP access"} = Repo.get_by(Scope, name: "mcp")
  end

  test "authorizes a dynamically registered MCP client with the mcp scope", %{conn: conn} do
    redirect_uri = "https://claude.ai/api/mcp/auth_callback"

    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Claude",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    assert %{"client_id" => client_id} = json_response(registration_conn, 201)

    {conn, _user} = log_in_user(build_conn(), %{email: "oauth-mcp@tuist.dev"})

    conn =
      get(conn, ~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "scope" => "mcp",
        "state" => "claude-state"
      })

    redirect = redirected_to(conn)
    assert redirect =~ redirect_uri
    assert redirect =~ "code="
    assert redirect =~ "state=claude-state"
    refute redirect =~ "invalid_scope"

    %{"code" => code} = redirect |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    token_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "code" => code
      })

    assert %{
             "access_token" => access_token,
             "refresh_token" => refresh_token,
             "token_type" => "bearer"
           } = json_response(token_conn, 200)

    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(access_token)
    assert is_binary(refresh_token)
  end

  test "keeps the resource indicator on the token so refreshes are accepted", %{conn: conn} do
    redirect_uri = "https://claude.ai/api/mcp/auth_callback"
    resource = "https://atlas.tuist.dev/mcp"

    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Claude Code",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    assert %{"client_id" => client_id} = json_response(registration_conn, 201)

    {conn, _user} = log_in_user(build_conn(), %{email: "oauth-mcp-resource@tuist.dev"})

    conn =
      get(conn, ~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "scope" => "mcp",
        "state" => "claude-state",
        "resource" => resource
      })

    %{"code" => code} =
      conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    token_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "code" => code,
        "resource" => resource
      })

    assert %{"access_token" => access_token, "refresh_token" => refresh_token} =
             json_response(token_conn, 200)

    assert %Token{resource: ^resource} = Repo.get_by(Token, value: access_token)

    refresh_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "client_id" => client_id,
        "refresh_token" => refresh_token,
        "resource" => resource
      })

    assert %{"access_token" => refreshed_access_token, "refresh_token" => _} =
             json_response(refresh_conn, 200)

    assert refreshed_access_token != access_token
    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(refreshed_access_token)

    assert %Token{resource: ^resource, previous_token: ^access_token} =
             Repo.get_by(Token, value: refreshed_access_token)
  end
end
