defmodule TuistWeb.PreviewsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(email: "tuist@tuist.dev")
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "POST /api/projects/:account_handle/:project_handle/previews/start" do
    test "starts multipart upload", %{conn: conn, user: user, project: project, account: account} do
      # Given
      upload_id = "upload-id"

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "name",
          supported_platforms: ["ios", "watchos"],
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app",
          git_branch: "main",
          git_commit_sha: "commit-sha",
          git_ref: "git-ref"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id

      {:ok, app_build} =
        AppBuilds.app_build_by_id(response["data"]["preview_id"], preload: [:preview])

      assert app_build.preview.display_name == "name"
      assert Enum.sort(app_build.supported_platforms) == [:ios, :watchos]
      assert response_data["preview_id"] == app_build.id

      assert Map.take(app_build.preview, [
               :display_name,
               :version,
               :bundle_identifier,
               :git_branch,
               :git_commit_sha,
               :git_ref,
               :created_by_account_id,
               :visibility
             ]) == %{
               display_name: "name",
               version: "1.0.0",
               bundle_identifier: "dev.tuist.app",
               git_branch: "main",
               git_commit_sha: "commit-sha",
               git_ref: "git-ref",
               created_by_account_id: account.id,
               visibility: nil
             }
    end

    test "starts multipart upload with track", %{conn: conn, user: user, project: project, account: account} do
      # Given
      upload_id = "upload-id"

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "name",
          track: "beta"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"

      {:ok, app_build} =
        AppBuilds.app_build_by_id(response["data"]["preview_id"], preload: [:preview])

      assert app_build.preview.track == "beta"
    end

    test "starts multipart upload of a bundle app build", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "name",
          type: "app_bundle"
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, app_build} = AppBuilds.app_build_by_id(response["data"]["preview_id"])
      assert app_build.type == :app_bundle
    end

    test "starts multipart upload of an ipa preview", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          type: "ipa"
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, app_build} = AppBuilds.app_build_by_id(response["data"]["preview_id"])
      assert app_build.type == :ipa
    end

    test "does not create a new preview when account and commit_sha are the same", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"
      git_commit_sha = "existing-commit-sha"

      _existing_preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_commit_sha: git_commit_sha,
          ran_by_account_id: account.id,
          bundle_identifier: "dev.tuist.updated",
          version: "2.0.0",
          supported_platforms: [:ios]
        )

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          type: "ipa",
          version: "2.0.0",
          bundle_identifier: "dev.tuist.updated",
          git_branch: "main",
          git_commit_sha: git_commit_sha,
          supported_platforms: ["ios", "macos"]
        )

      # Then
      response = json_response(conn, :ok)

      {:ok, app_build} = AppBuilds.app_build_by_id(response["data"]["preview_id"])
      [preview] = Repo.all(Preview)
      assert app_build.preview_id == preview.id
    end

    test "starts multipart upload with binary_id", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"
      binary_id = "550E8400-E29B-41D4-A716-446655440000"

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "App",
          type: "ipa",
          binary_id: binary_id
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"

      {:ok, app_build} = AppBuilds.app_build_by_id(response["data"]["app_build_id"])
      assert app_build.binary_id == binary_id
    end

    test "starts multipart upload with binary_id and build_version", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"
      binary_id = "550E8400-E29B-41D4-A716-446655440000"
      build_version = "123"

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "App",
          type: "ipa",
          binary_id: binary_id,
          build_version: build_version
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"

      {:ok, app_build} = AppBuilds.app_build_by_id(response["data"]["app_build_id"])
      assert app_build.binary_id == binary_id
      assert app_build.build_version == build_version
    end

    test "returns 409 conflict when uploading duplicate app build with same binary_id and build_version", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      binary_id = "550E8400-E29B-41D4-A716-446655440000"
      build_version = "123"

      _existing_app_build =
        AppBuildsFixtures.app_build_fixture(
          project: project,
          binary_id: binary_id,
          build_version: build_version
        )

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "App",
          type: "ipa",
          binary_id: binary_id,
          build_version: build_version
        )

      # Then
      response = json_response(conn, :conflict)
      assert response["status"] == "error"
      assert response["code"] == "duplicate_app_build"

      assert response["message"] ==
               "An app build with the same binary ID '#{binary_id}' and build version '#{build_version}' already exists."
    end

    test "allows uploading app build with same binary_id but different build_version", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "upload-id"
      binary_id = "550E8400-E29B-41D4-A716-446655440000"
      build_version_one = "123"
      build_version_two = "124"

      _existing_app_build =
        AppBuildsFixtures.app_build_fixture(
          project: project,
          binary_id: binary_id,
          build_version: build_version_one
        )

      expect(Storage, :multipart_start, fn _object_key, _actor ->
        upload_id
      end)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/start",
          display_name: "App",
          type: "ipa",
          binary_id: binary_id,
          build_version: build_version_two
        )

      # Then
      response = json_response(conn, :ok)
      assert response["status"] == "success"

      {:ok, app_build} = AppBuilds.app_build_by_id(response["data"]["app_build_id"])
      assert app_build.binary_id == binary_id
      assert app_build.build_version == build_version_two
    end

    test "returns error when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          conn
          |> put_req_header("content-type", "application/json")
          |> post(~p"/api/projects/#{account.name}/non-existing-project/previews/start")
        end)

      # Then
      assert JSON.decode!(payload) == %{
               "message" => "The project tuist/non-existing-project was not found."
             }
    end

    test "returns forbidden when user is not authorized to create preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  _actor,
                                                  [expires_in: _, content_length: 100] ->
        upload_url
      end)

      conn = Authentication.put_current_user(conn, user)

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

    test "generates platform-specific multipart url", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      app_build_id = "app-build-id"
      upload_id = "12344"
      part_number = 3
      platform = "ios"
      upload_url = "https://url.com/ios"

      object_key = "#{account.name}/#{project.name}/previews/#{app_build_id}.zip"

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  _actor,
                                                  [expires_in: _, content_length: 100] ->
        upload_url
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/generate-url",
          preview_id: app_build_id,
          platform: platform,
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
      assert response_data["url"] == "https://url.com/ios"
    end

    test "returns error when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          conn
          |> put_req_header("content-type", "application/json")
          |> post(~p"/api/projects/#{account.name}/non-existing-project/previews/generate-url",
            preview_id: "preview-id",
            multipart_upload_part: %{part_number: 0, upload_id: "upload-id"}
          )
        end)

      # Then
      assert JSON.decode!(payload) == %{
               "message" => "The project tuist/non-existing-project was not found."
             }
    end

    test "returns forbidden when user is not authorized to create preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      preview = AppBuildsFixtures.app_build_fixture(project: project)

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

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_commit_sha: "commit-sha",
          git_branch: "main"
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(preview: preview)

      object_key =
        "#{account.name}/#{project.name}/previews/#{app_build.id}.zip"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      expect(Storage, :multipart_complete_upload, fn ^object_key,
                                                     ^upload_id,
                                                     [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}],
                                                     _actor ->
        :ok
      end)

      expect(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: app_build.id,
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
               "qr_code_url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}/qr-code.png"),
               "icon_url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}/icon.png"),
               "device_url" =>
                 "itms-services://?action=download-manifest&url=#{url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}/manifest.plist")}",
               "bundle_identifier" => "dev.tuist.app",
               "display_name" => "App",
               "git_commit_sha" => "commit-sha",
               "git_branch" => "main",
               "track" => "",
               "version" => "1.0.0",
               "builds" => [
                 %{
                   "id" => app_build.id,
                   "type" => "app_bundle",
                   "supported_platforms" => ["ios"],
                   "url" => "https://mocked-url.com",
                   "inserted_at" => DateTime.to_iso8601(app_build.inserted_at),
                   "binary_id" => nil,
                   "build_version" => nil
                 }
               ],
               "supported_platforms" => ["ios"],
               "inserted_at" => DateTime.to_iso8601(preview.inserted_at),
               "created_by" => %{
                 "id" => account.id,
                 "handle" => account.name
               },
               "created_from_ci" => false
             }
    end

    test "completes multipart upload with track", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      upload_id = "1234"

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_commit_sha: "commit-sha",
          git_branch: "main",
          track: "beta"
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(preview: preview)

      expect(Storage, :multipart_complete_upload, fn _object_key, _upload_id, _parts, _actor ->
        :ok
      end)

      expect(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: app_build.id,
          multipart_upload_parts: %{
            parts: [],
            upload_id: upload_id
          }
        )

      # Then
      response = json_response(conn, :ok)

      assert response["track"] == "beta"
    end

    test "returns error when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          conn
          |> put_req_header("content-type", "application/json")
          |> post(~p"/api/projects/#{account.name}/non-existing-project/previews/complete",
            preview_id: "preview_id",
            multipart_upload_parts: %{
              parts: [],
              upload_id: "upload-id"
            }
          )
        end)

      # Then
      assert JSON.decode!(payload) == %{
               "message" => "The project tuist/non-existing-project was not found."
             }
    end

    test "returns error when preview doesn't exist", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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

    test "returns forbidden when user is not authorized to create app_build", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: "app_build_id",
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

    test "triggers pending QA runs for iOS simulator app builds", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      upload_id = "1234"

      project =
        ProjectsFixtures.project_fixture(
          account_id: account.id,
          vcs_provider: :github,
          vcs_repository_full_handle: "testaccount/testproject"
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_commit_sha: "commit-sha",
          git_branch: "main",
          git_ref: "refs/pull/123/merge"
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios_simulator]
        )

      QA.create_qa_run(%{
        app_build_id: nil,
        status: "pending",
        vcs_repository_full_handle: "testaccount/testproject",
        vcs_provider: :github,
        git_ref: "refs/pull/123/merge",
        prompt: "Test login functionality"
      })

      expect(Storage, :multipart_complete_upload, fn _object_key, _upload_id, _parts, _actor ->
        :ok
      end)

      expect(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      expect(QA, :enqueue_test_worker, fn qa_run ->
        assert qa_run.app_build_id == app_build.id
        assert qa_run.prompt == "Test login functionality"

        {:ok, %Oban.Job{}}
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{account.name}/#{project.name}/previews/complete",
          preview_id: app_build.id,
          multipart_upload_parts: %{
            parts: [],
            upload_id: upload_id
          }
        )

      # Then
      assert json_response(conn, :ok)
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
      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_commit_sha: "preview-commit-sha",
          git_branch: "main"
        )

      app_build =
        AppBuildsFixtures.app_build_fixture(preview: preview)

      object_key =
        "#{account.name}/#{project.name}/previews/#{app_build.id}.zip"

      expect(Storage, :generate_download_url, fn ^object_key, _actor, [expires_in: 3600] ->
        "https://url.com"
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

      # Then
      response = json_response(conn, :ok)

      assert response["url"] == "https://url.com"
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "preview-commit-sha"
      assert response["inserted_at"] == DateTime.to_iso8601(preview.inserted_at)

      assert response["created_by"] == %{
               "id" => account.id,
               "handle" => account.name
             }

      assert response["created_from_ci"] == false

      assert Enum.map(
               response["builds"],
               &Map.take(&1, ["id", "url", "type", "supported_platforms"])
             ) == [
               %{
                 "id" => app_build.id,
                 "url" => "https://url.com",
                 "type" => "app_bundle",
                 "supported_platforms" => ["ios"]
               }
             ]
    end

    test "returns not_found when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      preview = AppBuildsFixtures.app_build_fixture()

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          get(conn, ~p"/api/projects/#{account.name}/non-existing-project/previews/#{preview.id}")
        end)

      # Then
      assert JSON.decode!(payload) == %{
               "message" => "The project tuist/non-existing-project was not found."
             }
    end

    test "returns bad_request when the id is invalid", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/invalid-id")

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
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      preview = AppBuildsFixtures.app_build_fixture(project: project)

      # When
      conn = get(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

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
      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_commit_sha: "commit-sha-one",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "dev.tuist.app",
          git_branch: "main",
          git_commit_sha: "commit-sha-two",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      app_build_two = AppBuildsFixtures.app_build_fixture(preview: preview_two)

      expect(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      _preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "feature-branch",
          git_commit_sha: "commit-sha-three",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      _preview_four =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "AppTwo",
          git_branch: "main",
          git_commit_sha: "commit-sha-four",
          inserted_at: ~U[2021-01-01 03:00:00Z]
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?display_name=App&specifier=latest&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] == [
               %{
                 "id" => preview_two.id,
                 "url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}"),
                 "qr_code_url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}/qr-code.png"),
                 "icon_url" => url(~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}/icon.png"),
                 "device_url" =>
                   "itms-services://?action=download-manifest&url=#{url(~p"/#{account.name}/#{project.name}/previews/#{preview_two.id}/manifest.plist")}",
                 "bundle_identifier" => "dev.tuist.app",
                 "display_name" => "App",
                 "git_commit_sha" => "commit-sha-two",
                 "git_branch" => "main",
                 "track" => "",
                 "version" => "1.0.0",
                 "builds" => [
                   %{
                     "id" => app_build_two.id,
                     "type" => "app_bundle",
                     "supported_platforms" => ["ios"],
                     "url" => "https://mocked-url.com",
                     "inserted_at" => DateTime.to_iso8601(app_build_two.inserted_at),
                     "binary_id" => nil,
                     "build_version" => nil
                   }
                 ],
                 "supported_platforms" => [],
                 "inserted_at" => DateTime.to_iso8601(preview_two.inserted_at),
                 "created_by" => %{
                   "id" => account.id,
                   "handle" => account.name
                 },
                 "created_from_ci" => false
               }
             ]

      assert response["pagination_metadata"] == %{
               "total_count" => 2,
               "current_page" => 1,
               "page_size" => 1,
               "has_previous_page" => false,
               "has_next_page" => true,
               "total_pages" => 2
             }
    end

    test "lists a single latest preview for a given display name and supported platform", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          supported_platforms: [:ios, :macos]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "dev.tuist.app",
          supported_platforms: [:watchos, :macos]
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?display_name=App&specifier=latest&page_size=1&supported_platforms=ios"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert Enum.map(response["previews"], & &1["id"]) == [preview_one.id]
    end

    test "lists no previews when no preview for latest is available", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one",
          inserted_at: ~U[2021-01-01 00:00:00Z],
          git_branch: "feature"
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=latest&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert response["previews"] == []

      assert response["pagination_metadata"] == %{
               "has_next_page" => false,
               "has_previous_page" => false,
               "current_page" => 1,
               "page_size" => 1,
               "total_count" => 0,
               "total_pages" => 0
             }
    end

    test "lists previews with distinct bundle identifiers for the latest specifier", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      _preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.one"
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.one"
        )

      _preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.two"
        )

      _preview_four =
        AppBuildsFixtures.preview_fixture(
          project: project,
          bundle_identifier: "com.bundle.app.two"
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?distinct_field=bundle_identifier&specifier=latest"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert Enum.map(response["previews"], & &1["bundle_identifier"]) == [
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

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
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
        AppBuildsFixtures.app_build_fixture(
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

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
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
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one",
          git_branch: "feature-branch"
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one",
          git_branch: "main"
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=feature-branch&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert Enum.map(response["previews"], & &1["id"]) == [
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
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one",
          git_commit_sha: "36fa9d5c3cb9f1dd45f194035a665444ea2d316f",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      _preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one",
          git_commit_sha: "a8169b2276adc2a4fb8c41030e5c640541b46ef9",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=36fa9d5c3cb9f1dd45f194035a665444ea2d316f&page_size=1"
        )

      # Then
      response =
        json_response(conn, :ok)

      assert Enum.map(response["previews"], & &1["id"]) == [
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
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-one",
          git_commit_sha: "commit-sha-1",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-two",
          git_commit_sha: "commit-sha-2",
          inserted_at: ~U[2021-01-01 01:00:00Z]
        )

      preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "preview-three",
          git_commit_sha: "commit-sha-3",
          inserted_at: ~U[2021-01-01 02:00:00Z]
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      first_page_conn =
        get(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews?page_size=2")

      second_page_conn =
        get(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews?page_size=2&page=2")

      # Then
      first_page_response =
        json_response(first_page_conn, :ok)

      second_page_response = json_response(second_page_conn, :ok)

      assert Enum.map(first_page_response["previews"], & &1["id"]) == [
               preview_three.id,
               preview_two.id
             ]

      assert Enum.map(second_page_response["previews"], & &1["id"]) == [
               preview_one.id
             ]

      assert first_page_response["pagination_metadata"] == %{
               "total_count" => 3,
               "current_page" => 1,
               "page_size" => 2,
               "total_pages" => 2,
               "has_next_page" => true,
               "has_previous_page" => false
             }

      assert second_page_response["pagination_metadata"] == %{
               "total_count" => 3,
               "current_page" => 2,
               "page_size" => 2,
               "total_pages" => 2,
               "has_next_page" => false,
               "has_previous_page" => true
             }
    end

    test "returns not_found when project doesn't exist", %{
      conn: conn,
      user: user,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          get(
            conn,
            ~p"/api/projects/#{account.name}/non-existing-project/previews?specifier=latest&page_size=1"
          )
        end)

      # Then
      assert JSON.decode!(payload) == %{
               "message" => "The project tuist/non-existing-project was not found."
             }
    end

    test "returns forbidden when user is not authorized to read preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews?specifier=latest&page_size=1"
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to read preview"
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/previews/latest" do
    test "returns the latest preview on the same track", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      binary_id = "550E8400-E29B-41D4-A716-446655440000"
      build_version = "123"

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      _app_build_one =
        AppBuildsFixtures.app_build_fixture(preview: preview_one, binary_id: binary_id, build_version: build_version)

      preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "main",
          inserted_at: ~U[2021-01-02 00:00:00Z]
        )

      app_build_two = AppBuildsFixtures.app_build_fixture(preview: preview_two)

      expect(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/latest?binary_id=#{binary_id}&build_version=#{build_version}"
        )

      # Then
      response = json_response(conn, :ok)

      assert response["preview"]["id"] == preview_two.id
      assert response["preview"]["bundle_identifier"] == "com.example.app"
      assert response["preview"]["git_branch"] == "main"
      assert hd(response["preview"]["builds"])["id"] == app_build_two.id
    end

    test "returns nil when binary_id is not found", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      _preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app"
        )

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/latest?binary_id=nonexistent-id&build_version=123"
        )

      # Then
      response = json_response(conn, :ok)

      assert response["preview"] == nil
    end

    test "respects git_branch when finding latest preview", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      binary_id = "550E8400-E29B-41D4-A716-446655440001"
      build_version = "123"

      preview_main =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      _app_build_main =
        AppBuildsFixtures.app_build_fixture(preview: preview_main, binary_id: binary_id, build_version: build_version)

      _preview_feature =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "feature-branch",
          inserted_at: ~U[2021-01-02 00:00:00Z]
        )

      expect(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/latest?binary_id=#{binary_id}&build_version=#{build_version}"
        )

      # Then
      response = json_response(conn, :ok)

      assert response["preview"]["id"] == preview_main.id
      assert response["preview"]["git_branch"] == "main"
    end

    test "returns nil when no preview matches the track", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      binary_id = "550E8400-E29B-41D4-A716-446655440002"
      build_version = "123"

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: nil,
          git_branch: "main"
        )

      _app_build =
        AppBuildsFixtures.app_build_fixture(preview: preview, binary_id: binary_id, build_version: build_version)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/latest?binary_id=#{binary_id}&build_version=#{build_version}"
        )

      # Then
      response = json_response(conn, :ok)

      assert response["preview"] == nil
    end

    test "returns forbidden when user is not authorized", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/latest?binary_id=some-id&build_version=123"
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to read preview"
    end

    test "returns latest preview that has an app build matching the platform of the binary_id", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      binary_id = "550E8400-E29B-41D4-A716-446655440003"
      build_version = "123"

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "main",
          inserted_at: ~U[2021-01-01 00:00:00Z]
        )

      _app_build_one =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_one,
          binary_id: binary_id,
          build_version: build_version,
          supported_platforms: [:ios]
        )

      # This preview has no iOS app build, so it should be skipped
      preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "main",
          inserted_at: ~U[2021-01-02 00:00:00Z]
        )

      _app_build_macos_only =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_two,
          supported_platforms: [:macos]
        )

      # This is the latest preview with an iOS app build
      preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "com.example.app",
          git_branch: "main",
          inserted_at: ~U[2021-01-03 00:00:00Z]
        )

      _app_build_ios =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_three,
          supported_platforms: [:ios]
        )

      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://mocked-url.com" end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        get(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/latest?binary_id=#{binary_id}&build_version=#{build_version}"
        )

      # Then
      response = json_response(conn, :ok)

      # Should return preview_three (latest with iOS build), skipping preview_two (no iOS build)
      assert response["preview"]["id"] == preview_three.id
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/previews/:preview_id/icons" do
    test "return preview icon upload URL", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview = AppBuildsFixtures.preview_fixture(project: project)

      object_key =
        "#{account.name}/#{project.name}/previews/#{preview.id}/icon.png"

      expect(Storage, :generate_upload_url, fn ^object_key, _actor, [expires_in: 3600] ->
        "https://url.com"
      end)

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        post(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}/icons")

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
      conn = Authentication.put_current_user(conn, user)

      preview = AppBuildsFixtures.app_build_fixture()

      # When
      {_, _, payload} =
        assert_error_sent(:not_found, fn ->
          post(
            conn,
            ~p"/api/projects/#{account.name}/non-existing-project/previews/#{preview.id}/icons"
          )
        end)

      # Then
      assert JSON.decode!(payload) == %{
               "message" => "The project tuist/non-existing-project was not found."
             }
    end

    test "returns forbidden when user is not authorized to read preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      preview = AppBuildsFixtures.app_build_fixture(project: project)

      # When
      conn =
        post(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}/icons")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to create preview"
    end
  end

  describe "DELETE /api/projects/:account_handle/:project_handle/previews/:preview_id" do
    test "deletes a preview successfully", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      preview = AppBuildsFixtures.preview_fixture(project: project, created_by_account: account)
      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        delete(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

      # Then
      assert conn.status == 204

      assert Repo.get(Preview, preview.id) == nil
    end

    test "returns not_found when preview doesn't exist", %{
      conn: conn,
      user: user,
      project: project,
      account: account
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)
      non_existing_id = "00000000-0000-0000-0000-000000000000"

      # When
      conn =
        delete(
          conn,
          ~p"/api/projects/#{account.name}/#{project.name}/previews/#{non_existing_id}"
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Preview not found."
    end

    test "returns forbidden when user is not authorized to delete preview", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      preview = AppBuildsFixtures.preview_fixture(project: project)

      # When
      conn =
        delete(conn, ~p"/api/projects/#{account.name}/#{project.name}/previews/#{preview.id}")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "tuist is not authorized to delete preview"
    end
  end
end
