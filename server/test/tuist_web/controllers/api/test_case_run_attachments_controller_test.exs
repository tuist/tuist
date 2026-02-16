defmodule TuistWeb.API.TestCaseRunAttachmentsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
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
      test_case_run_id = UUIDv7.generate()

      stub(Tests, :create_test_case_run_attachment, fn attrs ->
        assert attrs.test_case_run_id == test_case_run_id
        assert attrs.file_name == "crash-report.ips"
        assert attrs.content_type == "application/x-ips"
        {:ok, %{id: attrs.id}}
      end)

      stub(Storage, :generate_upload_url, fn _key, _account, _opts ->
        "https://s3.example.com/upload?signed=true"
      end)

      # When
      conn =
        post(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/attachments",
          %{
            test_case_run_id: test_case_run_id,
            file_name: "crash-report.ips",
            content_type: "application/x-ips"
          }
        )

      # Then
      response = json_response(conn, :created)
      assert response["id"]
      assert response["upload_url"] == "https://s3.example.com/upload?signed=true"
      assert response["expires_at"]
    end

    test "returns bad request when attachment creation fails", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      stub(Tests, :create_test_case_run_attachment, fn _attrs ->
        {:error, %Ecto.Changeset{}}
      end)

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
      response = json_response(conn, :bad_request)
      assert response["message"] == "The request parameters are invalid"
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

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-case-runs/:test_case_run_id/attachments/:file_name" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns download URL for existing attachment", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_run_id = UUIDv7.generate()
      attachment_id = UUIDv7.generate()

      stub(Tests, :get_attachment, fn run_id, file_name ->
        assert run_id == test_case_run_id
        assert file_name == "crash-report.ips"
        {:ok, %{id: attachment_id}}
      end)

      stub(Storage, :generate_download_url, fn _key, _account, _opts ->
        "https://s3.example.com/download?signed=true"
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-case-runs/#{test_case_run_id}/attachments/crash-report.ips"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["url"] == "https://s3.example.com/download?signed=true"
    end

    test "returns 404 when attachment is not found", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      stub(Tests, :get_attachment, fn _run_id, _file_name ->
        {:error, :not_found}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-case-runs/#{UUIDv7.generate()}/attachments/nonexistent.ips"
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Attachment not found."
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/test-case-runs/#{UUIDv7.generate()}/attachments/crash.ips"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
