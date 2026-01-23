defmodule TuistWeb.API.TestsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists only tests for the project", %{conn: conn, user: user, project: project} do
      {:ok, _test_one} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      {:ok, test_two} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      {:ok, _other_project_test} = RunsFixtures.test_fixture()

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests?page_size=1"
        )

      response = json_response(conn, :ok)

      assert length(response["tests"]) == 1
      assert hd(response["tests"])["id"] == test_two.id
    end

    test "returns forbidden response when the user doesn't have access to the project", %{conn: conn} do
      another_user = AccountsFixtures.user_fixture(preload: [:account])
      another_project = ProjectsFixtures.project_fixture(account_id: another_user.account.id)

      conn =
        get(conn, "/api/projects/#{another_user.account.name}/#{another_project.name}/tests")

      assert response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "shows a test run", %{conn: conn, user: user, project: project} do
      {:ok, test_run} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}"
        )

      response = json_response(conn, :ok)
      assert response["id"] == test_run.id
    end

    test "returns not found when the test run isn't in the project", %{conn: conn, user: user, project: project} do
      {:ok, other_test} = RunsFixtures.test_fixture()

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{other_test.id}"
        )

      assert response(conn, :not_found)
    end
  end
end
