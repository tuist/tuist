defmodule TuistWeb.API.TestCasesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Runs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/cases" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists test cases for the project", %{conn: conn, user: user, project: project} do
      {:ok, _test_run} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/cases?page_size=1"
        )

      response = json_response(conn, :ok)

      assert length(response["test_cases"]) == 1
    end

    test "returns forbidden response when the user doesn't have access to the project", %{conn: conn} do
      another_user = AccountsFixtures.user_fixture(preload: [:account])
      another_project = ProjectsFixtures.project_fixture(account_id: another_user.account.id)

      conn =
        get(conn, "/api/projects/#{another_user.account.name}/#{another_project.name}/tests/cases")

      assert response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/cases/:test_case_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "shows a test case", %{conn: conn, user: user, project: project} do
      {:ok, _test_run} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      {test_cases, _meta} = Runs.list_test_cases(project.id, %{page: 1, page_size: 1})
      test_case = hd(test_cases)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/cases/#{test_case.id}"
        )

      response = json_response(conn, :ok)
      assert response["id"] == test_case.id
    end

    test "returns not found when the test case isn't in the project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture()
      {:ok, _test_run} = RunsFixtures.test_fixture(project_id: other_project.id)

      {test_cases, _meta} = Runs.list_test_cases(other_project.id, %{page: 1, page_size: 1})
      test_case = hd(test_cases)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/cases/#{test_case.id}"
        )

      assert response(conn, :not_found)
    end
  end
end
