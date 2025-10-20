defmodule TuistWeb.API.AccessibleProjectsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Utilities
  alias TuistWeb.Authentication

  setup :verify_on_exit!

  setup do
    stub(Tuist.License, :get_license, fn -> {:ok, %{valid: true}} end)
    :ok
  end

  defp unique_project_name(prefix \\ "project") do
    "#{prefix}-#{Utilities.unique_integer(6)}"
  end

  describe "GET /api/accessible-projects" do
    test "returns accessible project handles for authenticated user", %{conn: conn} do
      user = AccountsFixtures.user_fixture(email: "accessible-user@tuist.io", preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, name: unique_project_name())

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/accessible-projects")

      response = json_response(conn, :ok)
      assert "#{user.account.name}/#{project.name}" in response
    end

    test "returns accessible project handles for authenticated account", %{conn: conn} do
      account = AccountsFixtures.account_fixture()
      project_one = ProjectsFixtures.project_fixture(account_id: account.id, name: unique_project_name("alpha"))
      project_two = ProjectsFixtures.project_fixture(account_id: account.id, name: unique_project_name("beta"))

      conn =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: []})
        |> get(~p"/api/accessible-projects")

      response = json_response(conn, :ok)

      expected_handles = [
        "#{account.name}/#{project_one.name}",
        "#{account.name}/#{project_two.name}"
      ]

      assert Enum.all?(expected_handles, &(&1 in response))
    end

    test "returns accessible project handle for project token", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(name: unique_project_name())

      conn =
        conn
        |> Authentication.put_current_project(project)
        |> get(~p"/api/accessible-projects")

      response = json_response(conn, :ok)
      assert response == ["#{project.account.name}/#{project.name}"]
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/accessible-projects")
      response = json_response(conn, :unauthorized)
      assert response["message"] =~ "You need to be authenticated"
    end
  end
end
