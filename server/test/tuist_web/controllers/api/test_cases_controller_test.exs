defmodule TuistWeb.API.TestCasesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-cases" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists test cases for a project", %{conn: conn, user: user, project: project} do
      # Given
      last_ran_at = NaiveDateTime.utc_now()

      test_case_one =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testExample1",
          module_name: "MyTests",
          last_ran_at: last_ran_at
        )

      test_case_two =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testExample2",
          module_name: "OtherTests",
          is_flaky: true,
          last_ran_at: last_ran_at
        )

      stub(Tests, :list_test_cases, fn _project_id, _options ->
        {[test_case_one, test_case_two],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 2,
           total_pages: 1
         }}
      end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases")

      # Then
      response = json_response(conn, :ok)

      assert length(response["test_cases"]) == 2

      first_test_case = Enum.find(response["test_cases"], &(&1["name"] == "testExample1"))
      assert first_test_case["module"]["name"] == "MyTests"
      assert first_test_case["suite"]["name"] == "TestSuite"
      assert first_test_case["is_flaky"] == false
      assert first_test_case["is_quarantined"] == false
      assert first_test_case["url"] =~ test_case_one.id

      second_test_case = Enum.find(response["test_cases"], &(&1["name"] == "testExample2"))
      assert second_test_case["module"]["name"] == "OtherTests"
      assert second_test_case["is_flaky"] == true
    end

    test "lists no test cases when there are none", %{conn: conn, user: user, project: project} do
      # Given
      stub(Tests, :list_test_cases, fn _project_id, _options ->
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
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases")

      # Then
      response = json_response(conn, :ok)

      assert response["test_cases"] == []
    end

    test "filters test cases by flaky status", %{conn: conn, user: user, project: project} do
      # Given
      last_ran_at = NaiveDateTime.utc_now()

      flaky_test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "flakyTest",
          is_flaky: true,
          last_ran_at: last_ran_at
        )

      expect(Tests, :list_test_cases, fn _project_id, options ->
        assert %{field: :is_flaky, op: :==, value: true} in options.filters

        {[flaky_test_case],
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
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases?flaky=true")

      # Then
      response = json_response(conn, :ok)

      assert length(response["test_cases"]) == 1
      assert hd(response["test_cases"])["name"] == "flakyTest"
      assert hd(response["test_cases"])["is_flaky"] == true
    end

    test "filters test cases by quarantined status", %{conn: conn, user: user, project: project} do
      # Given
      last_ran_at = NaiveDateTime.utc_now()

      quarantined_test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "quarantinedTest",
          is_quarantined: true,
          last_ran_at: last_ran_at
        )

      expect(Tests, :list_test_cases, fn _project_id, options ->
        assert %{field: :is_quarantined, op: :==, value: true} in options.filters

        {[quarantined_test_case],
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
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases?quarantined=true")

      # Then
      response = json_response(conn, :ok)

      assert length(response["test_cases"]) == 1
      assert hd(response["test_cases"])["name"] == "quarantinedTest"
      assert hd(response["test_cases"])["is_quarantined"] == true
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      # Given
      last_ran_at = NaiveDateTime.utc_now()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testExample",
          last_ran_at: last_ran_at
        )

      expect(Tests, :list_test_cases, fn _project_id, options ->
        assert options.page == 2
        assert options.page_size == 10

        {[test_case],
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 10,
           total_count: 11,
           total_pages: 2
         }}
      end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases?page=2&page_size=10")

      # Then
      response = json_response(conn, :ok)

      assert length(response["test_cases"]) == 1
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
      assert response["pagination_metadata"]["has_next_page"] == false
      assert response["pagination_metadata"]["has_previous_page"] == true
    end

    test "filters test cases by module_name", %{conn: conn, user: user, project: project} do
      # Given
      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testExample",
          module_name: "TargetModule",
          last_ran_at: NaiveDateTime.utc_now()
        )

      expect(Tests, :list_test_cases, fn _project_id, options ->
        assert %{field: :module_name, op: :==, value: "TargetModule"} in options.filters

        {[test_case],
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
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases?module_name=TargetModule")

      # Then
      response = json_response(conn, :ok)
      assert length(response["test_cases"]) == 1
    end

    test "filters test cases by name and suite_name", %{conn: conn, user: user, project: project} do
      # Given
      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testSpecific",
          suite_name: "MySuite",
          last_ran_at: NaiveDateTime.utc_now()
        )

      expect(Tests, :list_test_cases, fn _project_id, options ->
        assert %{field: :name, op: :==, value: "testSpecific"} in options.filters
        assert %{field: :suite_name, op: :==, value: "MySuite"} in options.filters

        {[test_case],
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
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases?name=testSpecific&suite_name=MySuite")

      # Then
      response = json_response(conn, :ok)
      assert length(response["test_cases"]) == 1
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/tests/test-cases")

      # Then
      assert json_response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-cases/:test_case_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns test case details", %{conn: conn, user: user, project: project} do
      # Given
      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testExample",
          module_name: "MyTests",
          suite_name: "MySuite",
          is_flaky: true,
          last_ran_at: NaiveDateTime.utc_now()
        )

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Analytics, :test_case_analytics_by_id, fn _id -> %{total_count: 50, failed_count: 2} end)
      stub(Analytics, :test_case_reliability_by_id, fn _id, _branch -> 96.0 end)
      stub(Analytics, :get_test_case_flakiness_rate, fn _tc -> 4.0 end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/#{test_case.id}")

      # Then
      response = json_response(conn, :ok)
      assert response["id"] == test_case.id
      assert response["name"] == "testExample"
      assert response["module"]["name"] == "MyTests"
      assert response["suite"]["name"] == "MySuite"
      assert response["is_flaky"] == true
      assert response["total_runs"] == 50
      assert response["failed_runs"] == 2
      assert response["reliability_rate"] == 96.0
      assert response["flakiness_rate"] == 4.0
      assert response["url"] =~ test_case.id
    end

    test "returns test case with nil suite", %{conn: conn, user: user, project: project} do
      # Given
      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "testExample",
          suite_name: nil,
          last_ran_at: NaiveDateTime.utc_now()
        )

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Analytics, :test_case_analytics_by_id, fn _id -> %{total_count: 10, failed_count: 0} end)
      stub(Analytics, :test_case_reliability_by_id, fn _id, _branch -> 100.0 end)
      stub(Analytics, :get_test_case_flakiness_rate, fn _tc -> 0.0 end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/#{test_case.id}")

      # Then
      response = json_response(conn, :ok)
      assert response["suite"] == nil
    end

    test "returns 404 when test case does not exist", %{conn: conn, user: user, project: project} do
      # Given
      stub(Tests, :get_test_case_by_id, fn _id -> {:error, :not_found} end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/#{UUIDv7.generate()}")

      # Then
      assert json_response(conn, :not_found)
    end

    test "returns 404 when test case belongs to a different project", %{conn: conn, user: user, project: project} do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: other_project.id,
          last_ran_at: NaiveDateTime.utc_now()
        )

      stub(Tests, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/#{test_case.id}")

      # Then
      assert json_response(conn, :not_found)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/tests/test-cases/#{UUIDv7.generate()}")

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
