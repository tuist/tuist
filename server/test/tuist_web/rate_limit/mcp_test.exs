defmodule TuistWeb.RateLimit.MCPTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.MCP

  describe "hit/1" do
    test "uses the user key when authenticated as user", %{conn: conn} do
      # Given
      user = %User{id: 123}
      timeout = to_timeout(minute: 1)
      bucket_size = 120

      stub(Authentication, :authenticated_subject, fn ^conn -> user end)
      stub(Tuist.Environment, :mcp_rate_limit_bucket_size, fn -> bucket_size end)

      expect(InMemory, :hit, fn "mcp:auth:user:123", ^timeout, ^bucket_size ->
        {:allow, 1}
      end)

      # When / Then
      assert MCP.hit(conn) == {:allow, 1}
    end

    test "uses the project key when authenticated as project", %{conn: conn} do
      # Given
      project = %Project{id: 456}
      timeout = to_timeout(minute: 1)
      bucket_size = 120

      stub(Authentication, :authenticated_subject, fn ^conn -> project end)
      stub(Tuist.Environment, :mcp_rate_limit_bucket_size, fn -> bucket_size end)

      expect(InMemory, :hit, fn "mcp:auth:project:456", ^timeout, ^bucket_size ->
        {:allow, 1}
      end)

      # When / Then
      assert MCP.hit(conn) == {:allow, 1}
    end

    test "uses the account key when authenticated as account", %{conn: conn} do
      # Given
      authenticated_account = %AuthenticatedAccount{account: %{id: 789}, scopes: []}
      timeout = to_timeout(minute: 1)
      bucket_size = 120

      stub(Authentication, :authenticated_subject, fn ^conn -> authenticated_account end)
      stub(Tuist.Environment, :mcp_rate_limit_bucket_size, fn -> bucket_size end)

      expect(InMemory, :hit, fn "mcp:auth:account:789", ^timeout, ^bucket_size ->
        {:allow, 1}
      end)

      # When / Then
      assert MCP.hit(conn) == {:allow, 1}
    end

    test "uses the IP key when unauthenticated", %{conn: conn} do
      # Given
      ip = "127.0.0.1"
      timeout = to_timeout(minute: 1)
      bucket_size = 120

      stub(Authentication, :authenticated_subject, fn ^conn -> nil end)
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Tuist.Environment, :mcp_rate_limit_bucket_size, fn -> bucket_size end)

      expect(InMemory, :hit, fn "mcp:unauth:127.0.0.1", ^timeout, ^bucket_size ->
        {:allow, 1}
      end)

      # When / Then
      assert MCP.hit(conn) == {:allow, 1}
    end
  end
end
