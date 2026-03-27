defmodule TuistWeb.API.TestSuiteRunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_run_id/suites" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns suite runs for a test run", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn id ->
        assert id == test_run_id
        {:ok, %{project_id: project.id}}
      end)

      stub(Tests, :list_test_suite_runs, fn _attrs ->
        {[
           %{
             name: "MySuite",
             status: :success,
             is_flaky: false,
             duration: 2000,
             test_case_count: 5,
             avg_test_case_duration: 400
           }
         ],
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
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites"
        )

      # Then
      response = json_response(conn, :ok)
      assert length(response["suites"]) == 1

      suite = hd(response["suites"])
      assert suite["name"] == "MySuite"
      assert suite["status"] == "success"
      assert suite["is_flaky"] == false
      assert suite["duration"] == 2000
      assert suite["test_case_count"] == 5
      assert suite["avg_test_case_duration"] == 400

      assert response["pagination_metadata"]["has_next_page"] == false
      assert response["pagination_metadata"]["current_page"] == 1
      assert response["pagination_metadata"]["total_count"] == 1
    end

    test "returns empty list when there are no suite runs", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Tests, :list_test_suite_runs, fn _attrs ->
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
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["suites"] == []
      assert response["pagination_metadata"]["total_count"] == 0
    end

    test "filters suite runs by status", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %{project_id: project.id}}
      end)

      expect(Tests, :list_test_suite_runs, fn attrs ->
        assert %{field: :status, op: :==, value: "failure"} in attrs.filters

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
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites?status=failure"
        )

      # Then
      assert json_response(conn, :ok)
    end

    test "filters suite runs by module name", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()
      module_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Tests, :list_test_module_runs, fn attrs ->
        assert %{field: :name, op: :==, value: "MyModule"} in attrs.filters

        {[%{id: module_run_id}],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 100,
           total_count: 1,
           total_pages: 1
         }}
      end)

      expect(Tests, :list_test_suite_runs, fn attrs ->
        assert %{field: :test_module_run_id, op: :in, value: [module_run_id]} in attrs.filters

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
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites?module_name=MyModule"
        )

      # Then
      assert json_response(conn, :ok)
    end

    test "filters by nil module run id when module name has no matching runs", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Tests, :list_test_module_runs, fn _attrs ->
        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 100,
           total_count: 0,
           total_pages: 0
         }}
      end)

      expect(Tests, :list_test_suite_runs, fn attrs ->
        assert %{field: :test_module_run_id, op: :==, value: nil} in attrs.filters

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
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites?module_name=NonExistent"
        )

      # Then
      assert json_response(conn, :ok)
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %{project_id: project.id}}
      end)

      expect(Tests, :list_test_suite_runs, fn attrs ->
        assert attrs.page == 2
        assert attrs.page_size == 5

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 5,
           total_count: 8,
           total_pages: 2
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites?page=2&page_size=5"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 5
      assert response["pagination_metadata"]["has_previous_page"] == true
      assert response["pagination_metadata"]["total_count"] == 8
    end

    test "returns 404 when test run does not exist", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:error, :not_found}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites"
        )

      # Then
      assert %{"message" => "Test run not found."} = json_response(conn, :not_found)
    end

    test "returns 404 when test run belongs to a different project", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      stub(Tests, :get_test, fn _id ->
        {:ok, %{project_id: other_project.id}}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/suites"
        )

      # Then
      assert %{"message" => "Test run not found."} = json_response(conn, :not_found)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/#{UUIDv7.generate()}/suites"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
