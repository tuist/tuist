defmodule TuistWeb.API.TestCaseRunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-cases/runs" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists runs filtered by test case id", %{conn: conn, user: user, project: project} do
      # Given
      test_case_id = UUIDv7.generate()

      test_case_run =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: 0,
          is_flaky: true,
          git_branch: "main"
        )

      stub(Tests, :list_test_case_runs, fn options ->
        assert %{field: :test_case_id, op: :==, value: test_case_id} in options.filters

        {[%{struct(TestCaseRun, test_case_run) | status: :success}],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs?test_case_id=#{test_case_id}"
        )

      # Then
      response = json_response(conn, :ok)
      assert length(response["test_case_runs"]) == 1

      run = hd(response["test_case_runs"])
      assert run["id"] == test_case_run.id
      assert run["status"] == "success"
      assert run["is_flaky"] == true
      assert run["git_branch"] == "main"
    end

    test "passes flaky filter to service", %{conn: conn, user: user, project: project} do
      # Given
      test_case_id = UUIDv7.generate()

      expect(Tests, :list_test_case_runs, fn options ->
        assert %{field: :is_flaky, op: :==, value: true} in options.filters
        assert %{field: :test_case_id, op: :==, value: test_case_id} in options.filters

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs?test_case_id=#{test_case_id}&flaky=true"
        )

      # Then
      assert json_response(conn, :ok)
    end

    test "supports pagination parameters", %{conn: conn, user: user, project: project} do
      # Given
      test_case_id = UUIDv7.generate()

      expect(Tests, :list_test_case_runs, fn options ->
        assert options.page == 2
        assert options.page_size == 5

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 5,
           total_count: 6,
           total_pages: 2
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs?test_case_id=#{test_case_id}&page=2&page_size=5"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 5
      assert response["pagination_metadata"]["total_count"] == 6
      assert response["pagination_metadata"]["has_previous_page"] == true
    end

    test "lists all runs when no filters are provided", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      stub(Tests, :list_test_case_runs, fn options ->
        assert options.filters == []

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["test_case_runs"] == []
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)
      test_case_id = UUIDv7.generate()

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/test-cases/runs?test_case_id=#{test_case_id}"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-cases/:test_case_id/runs (deprecated)" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists runs for a test case via legacy route", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_id = UUIDv7.generate()

      test_case_run =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: 0,
          is_flaky: true,
          git_branch: "main"
        )

      stub(Tests, :list_test_case_runs, fn options ->
        assert %{field: :test_case_id, op: :==, value: test_case_id} in options.filters

        {[%{struct(TestCaseRun, test_case_run) | status: :success}],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/#{test_case_id}/runs"
        )

      # Then
      response = json_response(conn, :ok)
      assert length(response["test_case_runs"]) == 1
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-cases/runs/:test_case_run_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns test case run with failures and repetitions", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_run =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          name: "testExample",
          module_name: "MyTests",
          suite_name: "MySuite",
          status: 1,
          is_flaky: true,
          git_branch: "main",
          git_commit_sha: "abc1234"
        )

      failure =
        RunsFixtures.test_case_failure_fixture(
          test_case_run_id: test_case_run.id,
          message: "Expected true, got false",
          path: "Tests/MyTests.swift",
          line_number: 42,
          issue_type: "assertion_failure"
        )

      repetition =
        RunsFixtures.test_case_run_repetition_fixture(
          test_case_run_id: test_case_run.id,
          repetition_number: 1,
          status: "failure",
          duration: 50
        )

      run_struct = %{
        struct(TestCaseRun, test_case_run)
        | status: :failure,
          git_commit_sha: "abc1234"
      }

      stub(Tests, :get_test_case_run_by_id, fn _id, _opts ->
        run_with_preloads = %{
          run_struct
          | failures: [struct(Tuist.Tests.TestCaseFailure, failure)],
            repetitions: [struct(Tuist.Tests.TestCaseRunRepetition, repetition)]
        }

        {:ok, run_with_preloads}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["id"] == test_case_run.id
      assert response["name"] == "testExample"
      assert response["module_name"] == "MyTests"
      assert response["suite_name"] == "MySuite"
      assert response["status"] == "failure"
      assert response["is_flaky"] == true
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "abc1234"
      assert response["test_run_id"] == test_case_run.test_run_id

      assert length(response["failures"]) == 1
      failure_response = hd(response["failures"])
      assert failure_response["message"] == "Expected true, got false"
      assert failure_response["path"] == "Tests/MyTests.swift"
      assert failure_response["line_number"] == 42
      assert failure_response["issue_type"] == "assertion_failure"

      assert length(response["repetitions"]) == 1
      repetition_response = hd(response["repetitions"])
      assert repetition_response["repetition_number"] == 1
      assert repetition_response["status"] == "failure"
      assert repetition_response["duration"] == 50
    end

    test "returns 404 when test case run does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      stub(Tests, :get_test_case_run_by_id, fn _id, _opts -> {:error, :not_found} end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{UUIDv7.generate()}"
        )

      # Then
      assert json_response(conn, :not_found)
    end

    test "returns 404 when test case run belongs to a different project", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      test_case_run =
        RunsFixtures.test_case_run_fixture(project_id: other_project.id)

      run_struct = %{
        struct(TestCaseRun, test_case_run)
        | status: :success,
          failures: [],
          repetitions: []
      }

      stub(Tests, :get_test_case_run_by_id, fn _id, _opts -> {:ok, run_struct} end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}"
        )

      # Then
      assert json_response(conn, :not_found)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/test-cases/runs/#{UUIDv7.generate()}"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
