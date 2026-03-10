defmodule TuistWeb.API.UploadsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup :verify_on_exit!

  describe "POST /api/projects/:account_handle/:project_handle/uploads" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns upload with presigned URL for valid build_archive purpose", %{
      conn: conn,
      user: user,
      project: project
    } do
      stub(Storage, :generate_upload_url, fn _key, _account, _opts ->
        "https://s3.example.com/presigned"
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{user.account.name}/#{project.name}/uploads", %{
          purpose: "build_archive"
        })

      response = json_response(conn, 200)
      assert response["id"]
      assert response["purpose"] == "build_archive"
      assert response["upload_url"] == "https://s3.example.com/presigned"
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{project.account.name}/#{project.name}/uploads", %{
          purpose: "build_archive"
        })

      assert json_response(conn, :forbidden)
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/uploads/start" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "starts a multipart upload", %{conn: conn, user: user, project: project} do
      upload_id = Ecto.UUID.generate()

      stub(Storage, :multipart_start, fn _key, _account ->
        "multipart-upload-id-123"
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{user.account.name}/#{project.name}/uploads/start", %{
          purpose: "build_archive",
          id: upload_id
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"]["upload_id"] == "multipart-upload-id-123"
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/uploads/generate-url" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "generates a signed URL for a part", %{conn: conn, user: user, project: project} do
      upload_id = Ecto.UUID.generate()

      stub(Storage, :multipart_generate_url, fn _key, _upload_id, _part_number, _account, _opts ->
        "https://s3.example.com/part-upload-url"
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{user.account.name}/#{project.name}/uploads/generate-url", %{
          purpose: "build_archive",
          id: upload_id,
          multipart_upload_part: %{
            part_number: 1,
            upload_id: "multipart-upload-id-123"
          }
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"]["url"] == "https://s3.example.com/part-upload-url"
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/uploads/complete" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "completes a multipart upload", %{conn: conn, user: user, project: project} do
      upload_id = Ecto.UUID.generate()

      stub(Storage, :multipart_complete_upload, fn _key, _upload_id, _parts, _account ->
        :ok
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{user.account.name}/#{project.name}/uploads/complete", %{
          purpose: "build_archive",
          id: upload_id,
          multipart_upload_parts: %{
            upload_id: "multipart-upload-id-123",
            parts: [
              %{part_number: 1, etag: "etag1"},
              %{part_number: 2, etag: "etag2"}
            ]
          }
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"] == %{}
    end
  end
end
