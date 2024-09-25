defmodule TuistWeb.PreviewsControllerTest do
  alias Tuist.Previews.Preview
  alias Tuist.Repo
  alias TuistWeb.Authentication
  alias Tuist.Storage
  alias Tuist.AccountsFixtures
  alias Tuist.Accounts
  alias Tuist.ProjectsFixtures
  use TuistWeb.ConnCase, async: false
  use Mimic

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")
    account = Accounts.get_account_from_user(user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "POST /api/projects/:account_handle/:project_handle/previews/start" do
    test "starts multipart upload", %{conn: conn, user: user, project: project, account: account} do
      # Given
      upload_id = "upload-id"

      Storage
      |> expect(:multipart_start, fn _ ->
        upload_id
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start")

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
      assert response_data["preview_id"] == Repo.all(Preview) |> hd() |> Map.get(:id)
    end

    test "starts multipart upload with a preview name", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"

      Storage
      |> expect(:multipart_start, fn _ ->
        upload_id
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "preview-name"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
      assert Repo.all(Preview) |> hd() |> Map.get(:display_name) == "preview-name"
    end

    test "returns error when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/non-existing-project/previews/start")

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project tuist/non-existing-project was not found."
    end

    test "returns forbidden when user is not authorized to create preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to create preview"
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/previews/generate-url" do
    test "generates multipart url", %{conn: conn, user: user, project: project, account: account} do
      # Given
      preview_id = "preview-id"
      upload_id = "12344"
      part_number = "3"
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview_id}.zip"

      Storage
      |> expect(:multipart_generate_url, fn ^object_key,
                                            ^upload_id,
                                            ^part_number,
                                            [expires_in: _] ->
        upload_url
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/generate-url",
          preview_id: preview_id,
          multipart_upload_part: %{part_number: part_number, upload_id: upload_id}
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["url"] == "https://url.com"
    end

    test "returns error when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/non-existing-project/previews/generate-url",
          preview_id: "preview-id",
          multipart_upload_part: %{part_number: 0, upload_id: "upload-id"}
        )

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project tuist/non-existing-project was not found."
    end

    test "returns forbidden when user is not authorized to create preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/generate-url",
          preview_id: "preview-id",
          multipart_upload_part: %{part_number: 0, upload_id: "upload-id"}
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to create preview"
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/previews/complete" do
    test "completes multipart upload", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "1234"
      preview_id = "preview-id"

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview_id}.zip"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      Storage
      |> expect(:multipart_complete_upload, fn ^object_key,
                                               ^upload_id,
                                               [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: preview_id,
          multipart_upload_parts: %{
            parts: parts,
            upload_id: upload_id
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview_id}")
             }
    end

    test "returns error when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/non-existing-project/previews/complete",
          preview_id: "preview_id",
          multipart_upload_parts: %{
            parts: [],
            upload_id: "upload-id"
          }
        )

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project tuist/non-existing-project was not found."
    end

    test "returns forbidden when user is not authorized to create preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: "preview_id",
          multipart_upload_parts: %{
            parts: [],
            upload_id: "upload-id"
          }
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to create preview"
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/previews/:preview_id" do
    test "return preview download URL", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_id = "preview-id"

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview_id}.zip"

      Storage
      |> expect(:generate_download_url, fn ^object_key, expires_in: 3600 ->
        "https://url.com"
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview_id}")

      # Then
      response = json_response(conn, :ok)

      assert response["url"] == "https://url.com"
    end

    test "returns not_found when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/non-existing-project/previews/preview-id")

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project tuist/non-existing-project was not found."
    end

    test "returns forbidden when user is not authorized to read preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews/preview-id")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to read preview"
    end
  end
end
