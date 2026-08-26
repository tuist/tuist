defmodule TuistWeb.RateLimit.AuthorizationTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.Authorization

  describe "hit/1" do
    test "uses the user key when authenticated as user", %{conn: conn} do
      # Given
      timeout = to_timeout(minute: 1)
      stub(Authentication, :authenticated_subject, fn ^conn -> %User{id: 123} end)

      expect(RateLimit, :hit, fn
        "authorization-denied:user:123", [limit: 300, window: ^timeout] ->
          {:allow, 1}
      end)

      # When / Then
      assert Authorization.hit(conn) == {:allow, 1}
    end

    test "uses the project key when authenticated as project", %{conn: conn} do
      # Given
      timeout = to_timeout(minute: 1)
      stub(Authentication, :authenticated_subject, fn ^conn -> %Project{id: 456} end)

      expect(RateLimit, :hit, fn
        "authorization-denied:project:456", [limit: 300, window: ^timeout] ->
          {:allow, 1}
      end)

      # When / Then
      assert Authorization.hit(conn) == {:allow, 1}
    end

    test "uses the account key when authenticated as account", %{conn: conn} do
      # Given
      timeout = to_timeout(minute: 1)

      stub(Authentication, :authenticated_subject, fn ^conn ->
        %AuthenticatedAccount{account: %{id: 789}, scopes: []}
      end)

      expect(RateLimit, :hit, fn
        "authorization-denied:account:789", [limit: 300, window: ^timeout] ->
          {:allow, 1}
      end)

      # When / Then
      assert Authorization.hit(conn) == {:allow, 1}
    end

    test "uses the IP key when there is no authenticated subject", %{conn: conn} do
      # Given
      timeout = to_timeout(minute: 1)
      stub(Authentication, :authenticated_subject, fn ^conn -> nil end)
      stub(TuistWeb.RemoteIp, :get, fn ^conn -> "127.0.0.1" end)

      expect(RateLimit, :hit, fn
        "authorization-denied:ip:127.0.0.1", [limit: 300, window: ^timeout] ->
          {:allow, 1}
      end)

      # When / Then
      assert Authorization.hit(conn) == {:allow, 1}
    end
  end
end
