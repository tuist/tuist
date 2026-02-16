defmodule TuistWeb.API.TestsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_run_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns test run details with metrics", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      test_run = %Test{
        id: test_run_id,
        project_id: project.id,
        status: "success",
        duration: 5000,
        is_ci: true,
        is_flaky: false,
        scheme: "App",
        macos_version: "14.0",
        xcode_version: "15.0",
        model_identifier: "Mac15,6",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: ~N[2026-01-15 10:00:00]
      }

      stub(Tests, :get_test, fn id ->
        assert id == test_run_id
        {:ok, test_run}
      end)

      stub(Analytics, :get_test_run_metrics, fn id ->
        assert id == test_run_id

        %{
          total_count: 42,
          failed_count: 3,
          flaky_count: 1,
          avg_duration: 120
        }
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["id"] == test_run_id
      assert response["status"] == "success"
      assert response["duration"] == 5000
      assert response["is_ci"] == true
      assert response["is_flaky"] == false
      assert response["scheme"] == "App"
      assert response["macos_version"] == "14.0"
      assert response["xcode_version"] == "15.0"
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "abc123"
      assert response["total_test_count"] == 42
      assert response["failed_test_count"] == 3
      assert response["flaky_test_count"] == 1
      assert response["avg_test_duration"] == 120
    end

    test "returns 404 when test run does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      stub(Tests, :get_test, fn _id -> {:error, :not_found} end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{UUIDv7.generate()}"
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Test run not found."
    end

    test "returns 404 when test run belongs to a different project", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %Test{id: test_run_id, project_id: other_project.id}}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}"
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Test run not found."
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/#{UUIDv7.generate()}"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
