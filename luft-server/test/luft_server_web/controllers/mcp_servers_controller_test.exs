defmodule LuftServerWeb.MCPServersControllerTest do
  use LuftServerWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias LuftServer.MCPServers.Server
  alias LuftServer.NativeAuth
  alias LuftServer.Repo

  setup do
    Req.Test.set_req_test_to_shared()
    stub_scope(true)
    stub_oauth(self())
    %{bearer: bearer()}
  end

  test "a person adds a server, signs in through the app and removes it", %{bearer: bearer} do
    assert %{"server" => %{"id" => id, "name" => "mcp.example", "connected" => false}} =
             authorized(bearer)
             |> post("/api/me/mcp-servers", %{url: "https://mcp.example/mcp"})
             |> json_response(200)

    assert authorized(bearer)
           |> post("/api/me/mcp-servers", %{url: "http://mcp.example/mcp"})
           |> json_response(422)

    assert %{"url" => url} =
             authorized(bearer)
             |> post("/api/me/mcp-servers/#{id}/authorize")
             |> json_response(200)

    query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["redirect_uri"] =~ "/mcp-servers/callback"
    assert query["code_challenge_method"] == "S256"
    assert query["resource"] == "https://mcp.example"
    assert_received {:registered, %{"client_name" => "Luft"}}

    # The browser comes back to Luft, which hands the answer to the app as is.
    callback = get(build_conn(), "/mcp-servers/callback?state=#{query["state"]}&code=the-code")

    assert redirected_to(callback, 302) ==
             "luft://mcp-callback?state=#{query["state"]}&code=the-code"

    # Another person cannot complete it.
    assert other_bearer("2")
           |> authorized()
           |> post("/api/me/mcp-servers/complete", %{state: query["state"], code: "the-code"})
           |> json_response(404)

    assert %{"server" => %{"connected" => true}} =
             authorized(bearer)
             |> post("/api/me/mcp-servers/complete", %{state: query["state"], code: "the-code"})
             |> json_response(200)

    assert_received {:exchanged, %{"code" => "the-code", "client_id" => "client-1"}}

    # Single use.
    assert authorized(bearer)
           |> post("/api/me/mcp-servers/complete", %{state: query["state"], code: "the-code"})
           |> json_response(404)

    assert %{"servers" => [%{"id" => ^id, "connected" => true} = listed]} =
             authorized(bearer) |> get("/api/me/mcp-servers") |> json_response(200)

    refute Map.has_key?(listed, "access_token")
    # Saved encrypted, never as the token itself.
    %{rows: rows} = Repo.query!("SELECT access_token FROM mcp_servers")
    refute rows |> List.flatten() |> Enum.any?(&String.contains?(&1, "access-1"))

    assert authorized(bearer) |> delete("/api/me/mcp-servers/#{id}") |> response(204)

    assert %{"servers" => []} =
             authorized(bearer) |> get("/api/me/mcp-servers") |> json_response(200)
  end

  test "organization servers are listed for members and changed only by admins", %{
    bearer: bearer
  } do
    assert %{"server" => %{"id" => id}} =
             authorized(bearer)
             |> post("/api/accounts/team/mcp-servers", %{url: "https://mcp.example/mcp"})
             |> json_response(200)

    assert [%Server{owner: "account:100"}] = Repo.all(Server)

    stub_scope(false)

    assert %{"servers" => [%{"id" => ^id}]} =
             authorized(bearer) |> get("/api/accounts/team/mcp-servers") |> json_response(200)

    assert authorized(bearer)
           |> post("/api/accounts/team/mcp-servers/#{id}/authorize")
           |> json_response(403)

    assert authorized(bearer)
           |> delete("/api/accounts/team/mcp-servers/#{id}")
           |> json_response(403)

    # Personal servers are separate from the organization's.
    assert %{"servers" => []} =
             authorized(bearer) |> get("/api/me/mcp-servers") |> json_response(200)
  end

  test "people Tuist no longer lets use Luft can't add personal servers", %{bearer: bearer} do
    stub_scope(true, ["1"])

    assert authorized(bearer)
           |> post("/api/me/mcp-servers", %{url: "https://mcp.example/mcp"})
           |> json_response(403)

    assert authorized(bearer) |> get("/api/me/mcp-servers") |> json_response(403)
    assert Repo.all(Server) == []
  end

  test "sign-ins to one server are limited", %{bearer: bearer} do
    %{"server" => %{"id" => id}} =
      authorized(bearer)
      |> post("/api/me/mcp-servers", %{url: "https://mcp.example/mcp"})
      |> json_response(200)

    for _ <- 1..10 do
      authorized(bearer) |> post("/api/me/mcp-servers/#{id}/authorize") |> json_response(200)
    end

    # Removing and adding the server again doesn't reset the count.
    authorized(bearer) |> delete("/api/me/mcp-servers/#{id}") |> response(204)

    %{"server" => %{"id" => readded}} =
      authorized(bearer)
      |> post("/api/me/mcp-servers", %{url: "https://mcp.example/mcp"})
      |> json_response(200)

    assert authorized(bearer)
           |> post("/api/me/mcp-servers/#{readded}/authorize")
           |> json_response(429)
  end

  # `team` is an organization; `user-<sub>` is each person's own account,
  # which Tuist refuses for people in `denied`.
  defp stub_scope(admin, denied \\ []) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      ["Bearer upstream-" <> sub] = Plug.Conn.get_req_header(conn, "authorization")

      denied? = sub in denied

      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          Req.Test.json(conn, %{
            user_id: String.to_integer(sub),
            account_id: 100,
            organization_id: 10,
            can_create_threads: admin,
            people: []
          })

        "/api/accounts/user-" <> _ when denied? ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})

        "/api/accounts/user-" <> _ ->
          Req.Test.json(conn, %{
            user_id: String.to_integer(sub),
            account_id: 1000 + String.to_integer(sub),
            organization_id: nil,
            can_create_threads: true,
            people: []
          })
      end
    end)
  end

  # An MCP server at mcp.example whose authorization server is auth.example.
  defp stub_oauth(test) do
    Req.Test.stub(LuftServer.MCPServers, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.host, conn.request_path} do
        {"mcp.example", "/mcp"} ->
          conn
          |> Plug.Conn.put_resp_header(
            "www-authenticate",
            ~s(Bearer resource_metadata="https://mcp.example/.well-known/oauth-protected-resource")
          )
          |> Plug.Conn.send_resp(401, "")

        {"mcp.example", "/.well-known/oauth-protected-resource"} ->
          Req.Test.json(conn, %{
            resource: "https://mcp.example",
            authorization_servers: ["https://auth.example"]
          })

        {"auth.example", "/.well-known/oauth-authorization-server"} ->
          Req.Test.json(conn, %{
            issuer: "https://auth.example",
            authorization_endpoint: "https://auth.example/authorize",
            token_endpoint: "https://auth.example/token",
            registration_endpoint: "https://auth.example/register",
            code_challenge_methods_supported: ["S256"]
          })

        {"auth.example", "/register"} ->
          send(test, {:registered, Jason.decode!(body)})
          Req.Test.json(conn, %{client_id: "client-1"})

        {"auth.example", "/token"} ->
          send(test, {:exchanged, URI.decode_query(body)})
          Req.Test.json(conn, %{access_token: "access-1", token_type: "Bearer", expires_in: 3600})
      end
    end)
  end

  defp other_bearer(sub), do: bearer(sub)

  defp authorized(bearer) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> bearer)
    |> put_req_header("accept", "application/json")
  end

  defp bearer(sub \\ "1") do
    verifier = String.duplicate("v", 43)

    request = %{
      "client_id" => NativeAuth.client_id(),
      "response_type" => "code",
      "redirect_uri" => "luft://oauth-callback",
      "state" => "state",
      "code_challenge_method" => "S256",
      "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    }

    {:ok, callback, _session} =
      NativeAuth.complete(
        %{
          claims: %{"sub" => sub, "preferred_username" => "user-" <> sub},
          tokens: %{
            "access_token" => "upstream-" <> sub,
            "refresh_token" => "refresh",
            "expires_in" => 3600
          }
        },
        request
      )

    params = callback |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    {:ok, credentials} =
      NativeAuth.exchange(%{
        "grant_type" => "authorization_code",
        "client_id" => NativeAuth.client_id(),
        "redirect_uri" => "luft://oauth-callback",
        "code" => params["code"],
        "code_verifier" => verifier
      })

    credentials.access_token
  end
end
