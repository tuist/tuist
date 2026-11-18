defmodule TuistWeb.MCPServerOAuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.UserMCPServer
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    stub(SSRFGuard, :pin, fn url -> {:ok, url, URI.parse(url).host} end)

    stub(PinnedHTTP, :request, fn _method, url, opts ->
      assert url == "https://auth.example.com/token"
      assert URI.decode_query(opts[:body])["code"] == "code-1"
      assert URI.decode_query(opts[:body])["code_verifier"] == "verifier"
      {:ok, %{status: 200, headers: [], body: JSON.encode!(%{"access_token" => "access-1", "expires_in" => 3600})}}
    end)

    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, server} = MCPServers.add(user, %{"url" => "https://mcp.example.com/mcp", "name" => "Atlas"})

    server
    |> UserMCPServer.changeset(%{
      token_endpoint: "https://auth.example.com/token",
      client_id: "registered-client",
      pending_authorization:
        JSON.encode!(%{code_verifier: "verifier", redirect_uri: "https://tuist.dev/integrations/mcp/callback"}),
      pending_state_hash: :crypto.hash(:sha256, "state-1"),
      pending_expires_at: DateTime.add(DateTime.utc_now(:second), 600)
    })
    |> Repo.update!()

    %{conn: conn, user: user, server: server}
  end

  test "completes the sign-in and returns to the AI settings", %{conn: conn, user: user, server: server} do
    conn = conn |> log_in_user(user) |> get(~p"/integrations/mcp/callback", state: "state-1", code: "code-1")

    assert redirected_to(conn) == ~p"/#{user.account.name}/settings/ai"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Connected to Atlas."
    assert {:ok, %{access_token: "access-1"}} = MCPServers.credentials(user, server.id)
  end

  test "completes nothing in another user's session", %{conn: conn, user: user, server: server} do
    other_user = AccountsFixtures.user_fixture(preload: [:account])
    conn = conn |> log_in_user(other_user) |> get(~p"/integrations/mcp/callback", state: "state-1", code: "code-1")

    assert redirected_to(conn) == ~p"/#{other_user.account.name}/settings/ai"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not complete"
    assert {:error, :not_connected} = MCPServers.credentials(user, server.id)
  end
end
