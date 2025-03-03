defmodule TuistWeb.PreviewsControllerTest do
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.PreviewsFixtures
  alias Tuist.Previews.Preview
  alias Tuist.Repo
  alias TuistWeb.Authentication
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  use TuistTestSupport.Cases.ConnCase, async: false
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

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
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

    test "starts multipart upload with supported platforms", %{
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
          supported_platforms: ["ios", "watchos"]
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id

      assert Repo.all(Preview) |> hd() |> Map.get(:supported_platforms) |> Enum.sort() == [
               :ios,
               :watchos
             ]
    end

    test "starts multipart upload of a bundle preview", %{
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
          display_name: "preview-name",
          type: "app_bundle"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
      preview = Repo.all(Preview) |> hd()
      assert preview |> Map.get(:display_name) == "preview-name"
      assert preview |> Map.get(:type) == :app_bundle
    end

    test "starts multipart upload of an archive preview", %{
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
          display_name: "preview-name",
          type: "ipa",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
      preview = Repo.all(Preview) |> hd()
      assert preview |> Map.get(:display_name) == "preview-name"
      assert preview |> Map.get(:type) == :ipa
      assert preview |> Map.get(:version) == "1.0.0"
      assert preview |> Map.get(:bundle_identifier) == "com.tuist.app"
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
      part_number = 3
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview_id}.zip"

      Storage
      |> expect(:multipart_generate_url, fn ^object_key,
                                            ^upload_id,
                                            ^part_number,
                                            [expires_in: _, content_length: 100] ->
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
          multipart_upload_part: %{
            part_number: part_number,
            upload_id: upload_id,
            content_length: 100
          }
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
      preview = PreviewsFixtures.preview_fixture(project: project)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/generate-url",
          preview_id: preview.id,
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
      preview = PreviewsFixtures.preview_fixture(project: project)

      _command_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          preview_id: preview.id,
          git_commit_sha: "preview-commit-sha",
          git_branch: "main"
        )

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview.id}.zip"

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
          preview_id: preview.id,
          multipart_upload_parts: %{
            parts: parts,
            upload_id: upload_id
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => preview.id,
               "url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}"),
               "qr_code_url" =>
                 url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}/qr-code.png"),
               "icon_url" =>
                 url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}/icon.png"),
               "bundle_identifier" => "com.tuist.app",
               "display_name" => "App",
               "git_commit_sha" => "preview-commit-sha",
               "git_branch" => "main"
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

    test "returns error when preview doesn't exist", %{
      conn: conn,
      user: user,
      project: project,
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
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: "01930188-401e-7529-a9e8-84f6c71a406c",
          multipart_upload_parts: %{
            parts: [],
            upload_id: "upload-id"
          }
        )

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "Preview not found."
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
      preview = PreviewsFixtures.preview_fixture(project: project)

      _command_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          preview_id: preview.id,
          git_commit_sha: "preview-commit-sha",
          git_branch: "main"
        )

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview.id}.zip"

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
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

      # Then
      response = json_response(conn, :ok)

      assert response["url"] == "https://url.com"
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "preview-commit-sha"
    end

    test "return preview when command_event is not found", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview = PreviewsFixtures.preview_fixture(project: project)

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview.id}.zip"

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
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

      # Then
      response = json_response(conn, :ok)

      assert response["url"] == "https://url.com"
      assert response["git_branch"] == nil
      assert response["git_commit_sha"] == nil
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

      preview = PreviewsFixtures.preview_fixture()

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/non-existing-project/previews/#{preview.id}")

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The project tuist/non-existing-project was not found."
    end

    test "returns bad_request when the id is invalid", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews/invalid-id")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "The provided preview ID invalid-id doesn't have a valid format."
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
      preview = PreviewsFixtures.preview_fixture(project: project)

      # When
      conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to read preview"
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/previews" do
    test "lists a single latest preview for a given display name", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.tuist.app"
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00],
          git_branch: "main",
          git_commit_sha: "commit-sha-two"
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      _command_event_three =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_three.id,
          created_at: ~N[2021-01-01 02:00:00],
          git_branch: "feature-branch"
        )

      preview_four =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "AppTwo"
        )

      _command_event_four =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_four.id,
          created_at: ~N[2021-01-01 02:30:00],
          git_branch: "main"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?display_name=App&specifier=latest&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] == [
               %{
                 "id" => preview_two.id,
                 "url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}"),
                 "qr_code_url" =>
                   url(
                     ~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}/qr-code.png"
                   ),
                 "icon_url" =>
                   url(~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}/icon.png"),
                 "bundle_identifier" => "com.tuist.app",
                 "display_name" => "App",
                 "git_commit_sha" => "commit-sha-two",
                 "git_branch" => "main"
               }
             ]
    end

    test "lists a single latest preview for a given display name and supported platform", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:ios, :macos]
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00],
          git_branch: "main"
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.tuist.app",
          supported_platforms: [:watchos, :macos]
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00],
          git_branch: "main"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?display_name=App&specifier=latest&page_size=1&supported_platforms=ios"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] |> Enum.map(& &1["id"]) == [preview_one.id]
    end

    test "lists no previews when no preview for latest is available", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00]
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=latest&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] == []
    end

    test "lists previews with distinct bundle identifiers for the latest specifier", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.one"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00],
          git_branch: "main"
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.one"
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00],
          git_branch: "main"
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.two"
        )

      _command_event_three =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_three.id,
          created_at: ~N[2021-01-01 02:00:00],
          git_branch: "main"
        )

      preview_four =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.two"
        )

      _command_event_four =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_four.id,
          created_at: ~N[2021-01-01 02:30:00],
          git_branch: "feature-branch"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?distinct_field=bundle_identifier&specifier=latest"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] |> Enum.map(& &1["bundle_identifier"]) == [
               "com.bundle.app.one",
               "com.bundle.app.two"
             ]
    end

    test "does not list any previews with distinct bundle identifiers for the latest specifier when the only preview has a nil preview_id",
         %{
           conn: conn,
           user: user,
           project: project,
           account: account
         } do
      # Given
      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: nil,
          created_at: ~N[2021-01-01 00:00:00],
          git_branch: "main"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?distinct_field=bundle_identifier&specifier=latest"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] == []
    end

    test "does not list any previews with distinct bundle identifiers for the latest specifier when the only preview has a nil bundle_identifier",
         %{
           conn: conn,
           user: user,
           project: project,
           account: account
         } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          bundle_identifier: nil
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00],
          git_branch: "main"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?distinct_field=bundle_identifier&specifier=latest"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] == []
    end

    test "lists a single preview from feature branch", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 01:00:00],
          git_branch: "feature-branch"
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 02:00:00],
          git_branch: "main"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=feature-branch&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] |> Enum.map(& &1["id"]) == [
               preview_one.id
             ]
    end

    test "lists a single preview for a git commit SHA", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 01:00:00],
          git_commit_sha: "36fa9d5c3cb9f1dd45f194035a665444ea2d316f"
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 02:00:00],
          git_commit_sha: "a8169b2276adc2a4fb8c41030e5c640541b46ef9"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=36fa9d5c3cb9f1dd45f194035a665444ea2d316f&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] |> Enum.map(& &1["id"]) == [
               preview_one.id
             ]
    end

    test "lists previews page by two", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_one.id,
          created_at: ~N[2021-01-01 00:00:00]
        )

      preview_two =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_two.id,
          created_at: ~N[2021-01-01 01:00:00]
        )

      preview_three =
        PreviewsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one"
        )

      _command_event_three =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          project_id: project.id,
          preview_id: preview_three.id,
          created_at: ~N[2021-01-01 02:00:00]
        )

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      first_page_conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews?page_size=2")

      second_page_conn =
        conn
        |> get(~p"/api/projects/#{account.name}/#{project.name}/previews?page_size=2&page=2")

      # Then
      first_page_response =
        json_response(first_page_conn, :ok)

      second_page_response = json_response(second_page_conn, :ok)

      assert first_page_response["previews"] |> Enum.map(& &1["id"]) == [
               preview_three.id,
               preview_two.id
             ]

      assert second_page_response["previews"] |> Enum.map(& &1["id"]) == [
               preview_one.id
             ]
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
        |> get(
          ~p"/api/projects/#{account.name}/non-existing-project/previews?specifier=latest&page_size=1"
        )

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
        |> get(
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=latest&page_size=1"
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to read preview"
    end
  end

  describe "PUST /api/projects/:account_handle/:project_handle/previews/:preview_id/icons" do
    test "return preview upload URL", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview = PreviewsFixtures.preview_fixture(project: project)

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview.id}/icon.png"

      Storage
      |> expect(:generate_upload_url, fn ^object_key, expires_in: 3600 ->
        "https://url.com"
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}/icons")

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

      preview = PreviewsFixtures.preview_fixture()

      # When
      conn =
        conn
        |> post(
          ~p"/api/projects/#{account.name}/non-existing-project/previews/#{preview.id}/icons"
        )

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
      preview = PreviewsFixtures.preview_fixture(project: project)

      # When
      conn =
        conn
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}/icons")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to create preview"
    end
  end
end
