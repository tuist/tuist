defmodule TuistWeb.API.TestCaseRunAttachmentsControllerTest do
  use TuistTestSupport.Cases.ConnCase, clickhouse: true
  use Mimic

  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/test-cases/runs/:test_case_run_id/attachments" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns attachments for a test case run", %{conn: conn, user: user, project: project} do
      # Given
      test_case_run_id = UUIDv7.generate()
      attachment_id = UUIDv7.generate()

      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test_case_run_by_id, fn id, _opts ->
        assert id == test_case_run_id

        {:ok,
         %{
           project_id: project.id,
           attachments: [
             %{
               id: attachment_id,
               test_run_id: test_run_id,
               file_name: "screenshot.png"
             }
           ]
         }}
      end)

      stub(Storage, :generate_download_url, fn _key, _account, _opts ->
        "https://s3.example.com/download?signed=true"
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run_id}/attachments"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["test_case_run_id"] == test_case_run_id
      assert length(response["attachments"]) == 1

      attachment = hd(response["attachments"])
      assert attachment["id"] == attachment_id
      assert attachment["file_name"] == "screenshot.png"
      assert attachment["type"] == "image"
      assert attachment["download_url"] == "https://s3.example.com/download?signed=true"
    end

    test "returns empty attachments list when test case run has no attachments", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_run_id = UUIDv7.generate()

      stub(Tests, :get_test_case_run_by_id, fn _id, _opts ->
        {:ok, %{project_id: project.id, attachments: []}}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run_id}/attachments"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["test_case_run_id"] == test_case_run_id
      assert response["attachments"] == []
    end

    test "returns correct type for various file extensions", %{conn: conn, user: user, project: project} do
      # Given
      test_case_run_id = UUIDv7.generate()

      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test_case_run_by_id, fn _id, _opts ->
        {:ok,
         %{
           project_id: project.id,
           attachments: [
             %{id: UUIDv7.generate(), test_run_id: test_run_id, file_name: "log.txt"},
             %{id: UUIDv7.generate(), test_run_id: test_run_id, file_name: "report.json"},
             %{id: UUIDv7.generate(), test_run_id: test_run_id, file_name: "crash.ips"},
             %{id: UUIDv7.generate(), test_run_id: test_run_id, file_name: "data.bin"}
           ]
         }}
      end)

      stub(Storage, :generate_download_url, fn _key, _account, _opts ->
        "https://s3.example.com/download"
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run_id}/attachments"
        )

      # Then
      response = json_response(conn, :ok)
      types = Enum.map(response["attachments"], & &1["type"])
      assert types == ["text", "json", "crash_report", "file"]
    end

    test "returns 404 when test case run does not exist", %{conn: conn, user: user, project: project} do
      # Given
      test_case_run_id = UUIDv7.generate()

      stub(Tests, :get_test_case_run_by_id, fn _id, _opts ->
        {:error, :not_found}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run_id}/attachments"
        )

      # Then
      assert %{"message" => "Test case run not found."} = json_response(conn, :not_found)
    end

    test "returns 404 when test case run belongs to a different project", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_run_id = UUIDv7.generate()
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      stub(Tests, :get_test_case_run_by_id, fn _id, _opts ->
        {:ok, %{project_id: other_project.id, attachments: []}}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run_id}/attachments"
        )

      # Then
      assert %{"message" => "Test case run not found."} = json_response(conn, :not_found)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/test-cases/runs/#{UUIDv7.generate()}/attachments"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end

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

    test "creates attachment with repetition_number", %{
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
            file_name: "screenshot.png",
            repetition_number: 2
          }
        )

      # Then
      response = json_response(conn, :created)
      assert response["id"]
      assert response["upload_url"] == "https://s3.example.com/upload?signed=true"
    end

    test "creates attachment with test_case_run_argument_id", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      test_case_run = RunsFixtures.test_case_run_fixture(project_id: project.id)
      argument_id = UUIDv7.generate()

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
            file_name: "arg-screenshot.png",
            test_case_run_argument_id: argument_id
          }
        )

      # Then
      response = json_response(conn, :created)
      assert response["id"]
      assert response["upload_url"] == "https://s3.example.com/upload?signed=true"
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
