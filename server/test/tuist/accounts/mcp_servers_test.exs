defmodule Tuist.Accounts.MCPServersTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.UserMCPServer
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @url "https://mcp.example.com/mcp"
  @redirect_uri "https://tuist.dev/integrations/mcp/callback"

  setup do
    stub(SSRFGuard, :pin, fn url -> {:ok, url, URI.parse(url).host} end)
    stub_mcp_server()
    %{user: AccountsFixtures.user_fixture()}
  end

  describe "the authorization flow" do
    test "discovers, registers, signs in with PKCE and stores the session encrypted", %{user: user} do
      {:ok, server} = MCPServers.add(user, %{"url" => @url, "name" => "Atlas"})
      assert {:ok, authorization_url} = MCPServers.start_authorization(user, server.id, @redirect_uri)

      %URI{host: "auth.example.com", path: "/authorize", query: query} = URI.parse(authorization_url)
      query = URI.decode_query(query)
      assert query["client_id"] == "registered-client"
      assert query["redirect_uri"] == @redirect_uri
      assert query["resource"] == @url
      assert query["scope"] == "mcp"
      assert query["code_challenge_method"] == "S256"

      parent = self()

      stub_mcp_server(
        token: fn form ->
          send(parent, {:token_request, form})
          {200, %{"access_token" => "access-1", "refresh_token" => "refresh-1", "expires_in" => 3600}}
        end
      )

      assert {:ok, _server} = MCPServers.complete_authorization(user, %{"state" => query["state"], "code" => "code-1"})

      assert_received {:token_request, form}
      assert form["grant_type"] == "authorization_code"
      assert form["resource"] == @url
      # The verifier sent with the code is the one the challenge was derived from.
      assert :sha256 |> :crypto.hash(form["code_verifier"]) |> Base.url_encode64(padding: false) ==
               query["code_challenge"]

      assert [%{name: "Atlas", url: @url, connected: true} = listed] = MCPServers.list(user)
      refute Map.has_key?(listed, :access_token)
      assert {:ok, %{url: @url, access_token: "access-1"}} = MCPServers.credentials(user, server.id)

      raw = Repo.one!(from s in "user_mcp_servers", select: %{access: s.access_token, refresh: s.refresh_token})
      refute raw.access =~ "access-1"
      refute raw.refresh =~ "refresh-1"
    end

    test "a state works once and only for the user who started it", %{user: user} do
      other_user = AccountsFixtures.user_fixture()
      {:ok, server} = MCPServers.add(user, %{"url" => @url})
      {:ok, authorization_url} = MCPServers.start_authorization(user, server.id, @redirect_uri)
      %{"state" => state} = authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert {:error, :not_found} = MCPServers.complete_authorization(other_user, %{"state" => state, "code" => "c"})
      assert {:ok, _} = MCPServers.complete_authorization(user, %{"state" => state, "code" => "c"})
      assert {:error, :not_found} = MCPServers.complete_authorization(user, %{"state" => state, "code" => "c"})
    end

    test "a denied or expired sign-in saves nothing", %{user: user} do
      {:ok, server} = MCPServers.add(user, %{"url" => @url})

      {:ok, url} = MCPServers.start_authorization(user, server.id, @redirect_uri)
      %{"state" => state} = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert {:error, :access_denied} =
               MCPServers.complete_authorization(user, %{"state" => state, "error" => "access_denied"})

      {:ok, url} = MCPServers.start_authorization(user, server.id, @redirect_uri)
      %{"state" => state} = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      Repo.update_all(UserMCPServer, set: [pending_expires_at: DateTime.add(DateTime.utc_now(), -1)])

      assert {:error, :authorization_expired} =
               MCPServers.complete_authorization(user, %{"state" => state, "code" => "c"})

      assert [%{connected: false}] = MCPServers.list(user)
    end

    test "rejects resource metadata for another origin and servers without PKCE", %{user: user} do
      {:ok, server} = MCPServers.add(user, %{"url" => @url})

      stub_mcp_server(resource: "https://attacker.example.net/mcp")
      assert {:error, :oauth_not_supported} = MCPServers.start_authorization(user, server.id, @redirect_uri)

      stub_mcp_server(code_challenge_methods: ["plain"])
      assert {:error, :oauth_not_supported} = MCPServers.start_authorization(user, server.id, @redirect_uri)
    end

    test "rejects authorization servers whose endpoints live on another origin (mix-up)", %{user: user} do
      {:ok, server} = MCPServers.add(user, %{"url" => @url})

      # The metadata sends the browser to an honest provider but keeps the token endpoint.
      stub_mcp_server(authorization_endpoint: "https://honest.example.org/authorize")
      assert {:error, :oauth_not_supported} = MCPServers.start_authorization(user, server.id, @redirect_uri)

      stub_mcp_server(token_endpoint: "https://collector.example.net/token")
      assert {:error, :oauth_not_supported} = MCPServers.start_authorization(user, server.id, @redirect_uri)
    end

    test "rejects a callback whose issuer is not the authorization server it started with", %{user: user} do
      {:ok, server} = MCPServers.add(user, %{"url" => @url})
      {:ok, url} = MCPServers.start_authorization(user, server.id, @redirect_uri)
      %{"state" => state} = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert {:error, :issuer_mismatch} =
               MCPServers.complete_authorization(user, %{
                 "state" => state,
                 "code" => "c",
                 "iss" => "https://honest.example.org"
               })

      assert [%{connected: false}] = MCPServers.list(user)
    end

    test "never carries a session over to another authorization server, even with the same client ID", %{user: user} do
      server =
        connected_server(user,
          issuer: "https://old-auth.example.com",
          token_endpoint: "https://old-auth.example.com/token",
          expires_at: nil
        )

      # The server now names auth.example.com, which also hands out "registered-client".
      assert {:ok, _url} = MCPServers.start_authorization(user, server.id, @redirect_uri)

      assert %UserMCPServer{access_token: nil, refresh_token: nil, issuer: "https://auth.example.com"} =
               Repo.get!(UserMCPServer, server.id)
    end

    test "only accepts public HTTPS endpoints", %{user: user} do
      assert {:error, :invalid_url} = MCPServers.add(user, %{"url" => "http://mcp.example.com/mcp"})
      assert {:error, :invalid_url} = MCPServers.add(user, %{"url" => "https://user:pass@mcp.example.com/mcp"})

      {:ok, server} = MCPServers.add(user, %{"url" => @url})
      stub(SSRFGuard, :pin, fn _url -> {:error, :private_ip_resolved} end)
      assert {:error, :provider_unavailable} = MCPServers.start_authorization(user, server.id, @redirect_uri)
    end
  end

  describe "credentials/2" do
    test "refreshes an expiring token, keeping a refresh token the server did not rotate", %{user: user} do
      server = connected_server(user, expires_at: DateTime.add(DateTime.utc_now(:second), 10))

      stub_mcp_server(
        token: fn %{"grant_type" => "refresh_token", "refresh_token" => "refresh-1"} ->
          {200, %{"access_token" => "access-2", "expires_in" => 3600}}
        end
      )

      assert {:ok, %{access_token: "access-2"}} = MCPServers.credentials(user, server.id)
      assert %UserMCPServer{refresh_token: "refresh-1", refreshing_until: nil} = Repo.get!(UserMCPServer, server.id)
    end

    test "requires a new sign-in when the refresh token is rejected", %{user: user} do
      server = connected_server(user, expires_at: DateTime.add(DateTime.utc_now(:second), -10))
      stub_mcp_server(token: fn _form -> {400, %{"error" => "invalid_grant"}} end)

      assert {:error, :reauthorization_required} = MCPServers.credentials(user, server.id)
      assert [%{connected: false}] = MCPServers.list(user)
    end

    test "keeps the session when the authorization server is unavailable", %{user: user} do
      server = connected_server(user, expires_at: DateTime.add(DateTime.utc_now(:second), -10))
      stub_mcp_server(token: fn _form -> {503, %{}} end)

      assert {:error, :refresh_failed} = MCPServers.credentials(user, server.id)
      assert %UserMCPServer{refresh_token: "refresh-1", refreshing_until: nil} = Repo.get!(UserMCPServer, server.id)
    end

    test "never returns another user's server", %{user: user} do
      server = connected_server(user, expires_at: nil)
      assert {:error, :not_found} = MCPServers.credentials(AccountsFixtures.user_fixture(), server.id)
      assert :ok = MCPServers.remove(AccountsFixtures.user_fixture(), server.id)
      assert {:ok, _} = MCPServers.credentials(user, server.id)
    end
  end

  defp connected_server(user, attrs) do
    {:ok, server} = MCPServers.add(user, %{"url" => @url})

    server
    |> UserMCPServer.changeset(
      Map.merge(
        %{
          token_endpoint: "https://auth.example.com/token",
          client_id: "registered-client",
          access_token: "access-1",
          refresh_token: "refresh-1"
        },
        Map.new(attrs)
      )
    )
    |> Repo.update!()
  end

  # A spec-compliant MCP server whose authorization server lives on another host.
  defp stub_mcp_server(options \\ []) do
    resource = Keyword.get(options, :resource, @url)
    methods = Keyword.get(options, :code_challenge_methods, ["S256"])
    authorization_endpoint = Keyword.get(options, :authorization_endpoint, "https://auth.example.com/authorize")
    token_endpoint = Keyword.get(options, :token_endpoint, "https://auth.example.com/token")
    token = Keyword.get(options, :token, fn _form -> {200, %{"access_token" => "access-1", "refresh_token" => "r"}} end)

    stub(PinnedHTTP, :request, fn method, url, opts ->
      case {method, url} do
        {"POST", @url} ->
          challenge =
            ~s(Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp", scope="mcp")

          {:ok, %{status: 401, headers: [{"WWW-Authenticate", challenge}], body: ""}}

        {"GET", "https://mcp.example.com/.well-known/oauth-protected-resource/mcp"} ->
          {:ok,
           %{
             status: 200,
             headers: [],
             body: JSON.encode!(%{"resource" => resource, "authorization_servers" => ["https://auth.example.com"]})
           }}

        {"GET", "https://auth.example.com/.well-known/oauth-authorization-server"} ->
          {:ok,
           %{
             status: 200,
             headers: [],
             body:
               JSON.encode!(%{
                 "issuer" => "https://auth.example.com",
                 "authorization_endpoint" => authorization_endpoint,
                 "token_endpoint" => token_endpoint,
                 "registration_endpoint" => "https://auth.example.com/register",
                 "code_challenge_methods_supported" => methods
               })
           }}

        {"POST", "https://auth.example.com/register"} ->
          {:ok, %{status: 201, headers: [], body: JSON.encode!(%{"client_id" => "registered-client"})}}

        {"POST", "https://auth.example.com/token"} ->
          {status, body} = token.(URI.decode_query(opts[:body]))
          {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}

        _other ->
          {:ok, %{status: 404, headers: [], body: JSON.encode!(%{})}}
      end
    end)
  end
end
