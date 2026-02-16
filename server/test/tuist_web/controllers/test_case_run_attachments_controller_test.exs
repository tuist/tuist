defmodule TuistWeb.TestCaseRunAttachmentsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "GET /:account_handle/:project_handle/tests/test-cases/runs/:test_case_run_id/attachments/:file_name" do
    test "redirects to the presigned download URL when user has permission", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: project.id)

      attachment =
        RunsFixtures.test_case_run_attachment_fixture(
          test_case_run_id: test_case_run.id,
          file_name: "crash-report.ips"
        )

      stub(Storage, :generate_download_url, fn _object_key, _account, _opts ->
        "https://s3.example.com/download?signed=true"
      end)

      # When
      conn =
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}/attachments/#{attachment.file_name}"
        )

      # Then
      assert redirected_to(conn) == "https://s3.example.com/download?signed=true"
    end

    test "returns 404 when attachment does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      test_case_run_id = UUIDv7.generate()

      # When
      conn =
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run_id}/attachments/nonexistent.ips"
        )

      # Then
      assert html_response(conn, 404)
    end

    test "returns 404 when user does not have permission", %{conn: conn} do
      # Given
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: owner.account.id)
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: project.id)

      attachment =
        RunsFixtures.test_case_run_attachment_fixture(
          test_case_run_id: test_case_run.id,
          file_name: "crash-report.ips"
        )

      conn = log_in_user(conn, other_user)

      # When
      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{owner.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}/attachments/#{attachment.file_name}"
        )
      end
    end
  end
end
