defmodule TuistWeb.DashboardControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "dashboard/2" do
    test "redirects to the last visited project when user has last_visited_project_id", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      ProjectsFixtures.project_fixture(account_id: account.id)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      Accounts.update_last_visited_project(user, project.id)

      conn = log_in_user(conn, user)

      # When
      conn = get(conn, ~p"/dashboard")

      # Then
      assert redirected_to(conn) == ~p"/#{account.name}/#{project.name}"
    end

    test "redirects to first available project when user has no last_visited_project_id", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn = log_in_user(conn, user)

      # When
      conn = get(conn, ~p"/dashboard")

      # Then
      assert redirected_to(conn) == ~p"/#{account.name}/#{project.name}"
    end

    test "redirects to projects page when user has no projects", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      conn = log_in_user(conn, user)

      # When
      conn = get(conn, ~p"/dashboard")

      # Then
      assert redirected_to(conn) == ~p"/#{account.name}/projects"
    end

    test "redirects to login when user is not authenticated", %{conn: conn} do
      # Given an unauthenticated connection

      # When
      conn = get(conn, ~p"/dashboard")

      # Then
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
