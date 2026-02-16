defmodule TuistWeb.API.CrashReportsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/projects/:account_handle/:project_handle/tests/crash-reports" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")

      %{conn: conn, user: user, project: project}
    end

    test "uploads a crash report successfully", %{conn: conn, user: user, project: project} do
      # Given
      test_case_run_id = UUIDv7.generate()
      attachment_id = UUIDv7.generate()

      stub(Tests, :upload_crash_report, fn attrs ->
        assert attrs.test_case_run_id == test_case_run_id
        assert attrs.test_case_run_attachment_id == attachment_id
        assert attrs.exception_type == "EXC_CRASH"
        assert attrs.signal == "SIGABRT"
        {:ok, %{id: attrs.id}}
      end)

      # When
      conn =
        post(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/crash-reports",
          %{
            test_case_run_id: test_case_run_id,
            test_case_run_attachment_id: attachment_id,
            exception_type: "EXC_CRASH",
            signal: "SIGABRT",
            exception_subtype: "KERN_INVALID_ADDRESS",
            triggered_thread_frames: "0  libswiftCore.dylib  _assertionFailure + 156"
          }
        )

      # Then
      assert json_response(conn, :ok) == %{}
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        post(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/crash-reports",
          %{
            test_case_run_id: UUIDv7.generate(),
            test_case_run_attachment_id: UUIDv7.generate()
          }
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
