defmodule TuistWeb.API.MCPTransportControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts.UserMCPServer
  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.API.MCPTransportController

  defmodule Router do
    use Phoenix.Router

    import Phoenix.ConnTest, only: []

    pipeline :authenticated do
      plug :accepts, ["json"]
      plug Plug.Parsers, parsers: [:json], json_decoder: Jason
      plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
      plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :open_api}
    end

    scope "/api/me/mcp-servers/transport" do
      pipe_through :authenticated
      get "/", MCPTransportController, :index, log: false
      get "/:server_id/tools", MCPTransportController, :discover, log: false
      post "/:server_id/tools/call", MCPTransportController, :invoke, log: false
    end
  end

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, client} = Clients.create_client(%{redirect_uris: ["https://luft.invalid/callback"], name: "mcp-capability"})
    stub(Clients, :luft_server_client_id, fn -> client.id end)
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)

    server =
      Repo.insert!(%UserMCPServer{
        user_id: user.id,
        name: "Profile",
        url: "https://mcp.example.com/mcp",
        access_token: "private-mcp-token"
      })

    %{user: user, client: client, server: server}
  end

  test "only scoped personal app grants admit metadata; MCP scope is separately authoritative", ctx do
    assert nil |> request() |> json_response(401)
    assert ctx |> oauth("") |> request() |> json_response(403)
    conn = request(oauth(ctx, "luft:app"))
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert %{"builtin_mcp_allowed" => false, "servers" => [%{"id" => id, "endpoint" => endpoint}]} =
             json_response(conn, 200)

    assert id == ctx.server.id and byte_size(endpoint) == 64
    refute conn.resp_body =~ "private-mcp-token"
    refute conn.resp_body =~ "access_token"
    scoped = oauth(ctx, "luft:app mcp")
    assert %{"builtin_mcp_allowed" => true} = scoped |> request() |> json_response(200)
    Token |> Repo.get_by!(value: scoped) |> Ecto.Changeset.change(scope: "luft:app") |> Repo.update!()
    assert %{"builtin_mcp_allowed" => false} = scoped |> request() |> json_response(200)
  end

  test "feature flag, removed grant and current deactivation fail closed", ctx do
    bearer = oauth(ctx, "luft:app")
    stub(FeatureFlags, :luft_enabled?, fn _ -> false end)
    assert bearer |> request() |> json_response(403)
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    Token |> Repo.get_by!(value: bearer) |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
    assert bearer |> request() |> json_response(403)
    bearer = oauth(ctx, "luft:app")
    Repo.update!(Ecto.Changeset.change(ctx.user, disabled_at: DateTime.utc_now(:second)))
    assert bearer |> request() |> json_response(403)
  end

  test "other users see no connection and cannot call it", ctx do
    other = AccountsFixtures.user_fixture(preload: [:account])
    bearer = oauth(%{ctx | user: other}, "luft:app")
    assert %{"servers" => []} = bearer |> request() |> json_response(200)
    reject(PinnedHTTP, :request, 3)

    conn =
      request(bearer, "/#{ctx.server.id}/tools/call", %{endpoint: String.duplicate("a", 64), name: "read", arguments: %{}})

    assert %{"result" => %{"isError" => true}} = json_response(conn, 200)
    refute conn.resp_body =~ "private-mcp-token"
  end

  defp oauth(ctx, scope) do
    bearer =
      TokenGenerator.generate(:access_token, %Token{sub: to_string(ctx.user.id), client_id: ctx.client.id, scope: scope})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: ctx.client.id,
      sub: to_string(ctx.user.id),
      scope: scope
    })

    bearer
  end

  defp request(bearer, path \\ "", body \\ nil) do
    conn =
      Plug.Test.conn(
        if(body, do: :post, else: :get),
        "/api/me/mcp-servers/transport" <> path,
        if(body, do: JSON.encode!(body))
      )

    conn = put_req_header(conn, "content-type", "application/json")
    conn = if bearer, do: put_req_header(conn, "authorization", "Bearer " <> bearer), else: conn
    Router.call(conn, Router.init([]))
  end
end
