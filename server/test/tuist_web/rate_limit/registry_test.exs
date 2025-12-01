defmodule TuistWeb.RateLimit.RegistryTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.Registry

  describe "call/2" do
    test "allows request when rate limit is not exceeded for authenticated user with Project", %{
      conn: conn
    } do
      # Given
      project_id = 123
      ip = "127.0.0.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Authentication, :authenticated_subject, fn ^conn -> %Project{id: project_id} end)
      hit_key = "registry:auth:project:#{project_id}"
      timeout = to_timeout(minute: 1)

      expect(InMemory, :hit, fn ^hit_key, ^timeout, 100_000 ->
        {:allow, 1}
      end)

      # When
      result = Registry.call(conn, [])

      # Then
      assert result == conn
    end

    test "allows request when rate limit is not exceeded for authenticated user with AuthenticatedAccount",
         %{conn: conn} do
      # Given
      account_id = 456
      authenticated_account = %AuthenticatedAccount{account: %{id: account_id}, scopes: []}
      ip = "127.0.0.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)

      stub(Authentication, :authenticated_subject, fn ^conn ->
        authenticated_account
      end)

      hit_key = "registry:auth:account:#{account_id}"
      timeout = to_timeout(minute: 1)

      expect(InMemory, :hit, fn ^hit_key, ^timeout, 100_000 ->
        {:allow, 1}
      end)

      # When
      result = Registry.call(conn, [])

      # Then
      assert result == conn
    end

    test "allows request when rate limit is not exceeded for unauthenticated user", %{
      conn: conn
    } do
      # Given
      ip = "192.168.1.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Authentication, :authenticated_subject, fn ^conn -> nil end)
      hit_key = "registry:unauth:#{ip}"
      timeout = to_timeout(minute: 1)

      expect(InMemory, :hit, fn ^hit_key, ^timeout, 10_000 ->
        {:allow, 1}
      end)

      # When
      result = Registry.call(conn, [])

      # Then
      assert result == conn
    end

    test "denies request when rate limit is exceeded for authenticated user", %{conn: conn} do
      # Given
      project_id = 789
      ip = "127.0.0.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Authentication, :authenticated_subject, fn ^conn -> %Project{id: project_id} end)
      hit_key = "registry:auth:project:#{project_id}"
      timeout = to_timeout(minute: 1)

      expect(InMemory, :hit, fn ^hit_key, ^timeout, 100_000 ->
        {:deny, 100_000}
      end)

      # When
      result = Registry.call(conn, [])

      # Then
      assert result.status == 429
      assert result.halted
      assert result.resp_body =~ "You have made too many requests to the registry"
    end

    test "denies request when rate limit is exceeded for unauthenticated user", %{conn: conn} do
      # Given
      ip = "10.0.0.1"
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> ip end)
      stub(Authentication, :authenticated_subject, fn ^conn -> nil end)
      hit_key = "registry:unauth:#{ip}"
      timeout = to_timeout(minute: 1)

      expect(InMemory, :hit, fn ^hit_key, ^timeout, 10_000 ->
        {:deny, 10_000}
      end)

      # When
      result = Registry.call(conn, [])

      # Then
      assert result.status == 429
      assert result.halted
      assert result.resp_body =~ "You have made too many requests to the registry"
    end
  end
end
