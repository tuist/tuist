defmodule TuistWeb.API.TestCaseRunAttachmentsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/projects/:account_handle/:project_handle/tests/attachments" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")

      %{conn: conn, user: user, project: project}
    end

    test "creates attachment and returns presigned upload URL", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: project.id)

      stub(Storage, :generate_upload_url, fn _key, _account, _opts ->
        "https://s3.example.com/upload?signed=true"
      end)

      # When
      conn =
        post(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/attachments",
          %{
            test_case_run_id: test_case_run.id,
            file_name: "crash-report.ips"
          }
        )

      # Then
      response = json_response(conn, :created)
      assert response["id"]
      assert response["upload_url"] == "https://s3.example.com/upload?signed=true"
      assert response["expires_at"]
    end

    test "returns 404 when test case run belongs to a different project", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: other_project.id)

      # When
      conn =
        post(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/attachments",
          %{
            test_case_run_id: test_case_run.id,
            file_name: "crash-report.ips"
          }
        )

      # Then
      assert json_response(conn, :not_found)
    end

    test "returns 404 when test case run does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # When
      conn =
        post(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/attachments",
          %{
            test_case_run_id: UUIDv7.generate(),
            file_name: "crash-report.ips"
          }
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
        post(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/attachments",
          %{
            test_case_run_id: UUIDv7.generate(),
            file_name: "crash-report.ips"
          }
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
