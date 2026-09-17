defmodule AtlasWeb.MCPOAuthControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.MCP
  alias Atlas.MCP.OAuth
  alias Atlas.MCP.Proxy.Config

  setup :verify_on_exit!

  setup do
    stub(Config, :get, fn -> proxy_config() end)
    :ok
  end

  test "redirects to the upstream OAuth authorization URL", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "mcp-authorize@example.com"})

    conn = get(conn, ~p"/mcps/grafana/authorize")

    assert redirected_to(conn) =~ "https://grafana.example/oauth/authorize?"
    assert redirected_to(conn) =~ "client_id=atlas"
    assert redirected_to(conn) =~ "code_challenge_method=S256"
  end

  test "exchanges an OAuth code and stores the session", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "mcp-callback@example.com"})
    {:ok, server} = MCP.get_server("grafana")

    {:ok, authorization_url} =
      OAuth.authorization_url(
        server,
        user,
        "http://www.example.com/mcps/grafana/callback",
        "/admin/mcps"
      )

    state = authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")

    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.options.form["grant_type"] == "authorization_code"
      assert request.options.form["code"] == "oauth-code"
      assert request.options.form["client_secret"] == "secret"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "access_token" => "access-token",
           "refresh_token" => "refresh-token",
           "expires_in" => 3600
         }
       }}
    end)

    conn = get(conn, ~p"/mcps/grafana/callback?code=oauth-code&state=#{state}")

    assert redirected_to(conn) == "/admin/mcps"
    assert MCP.get_oauth_session(user, "grafana").access_token == "access-token"
  end

  defp proxy_config do
    [
      servers: [
        %{
          name: "grafana",
          url: "https://mcp.grafana.com/mcp",
          auth_type: "oauth2",
          authorization_url: "https://grafana.example/oauth/authorize",
          token_url: "https://grafana.example/oauth/token",
          client_id: "atlas",
          client_secret: "secret",
          scopes: ["dashboards:read"]
        }
      ]
    ]
  end
end
