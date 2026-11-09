defmodule TuistWeb.PreviewControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.AppBuilds
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn = log_in_user(conn, user)

    %{conn: conn, user: user}
  end

  describe "latest_badge/2" do
    test "redirects to the latest badge", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      # When
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest/badge.svg")

      # Then
      assert redirected_to(conn) == ~p"/app/images/previews-badge.svg"
    end
  end

  describe "latest/2" do
    test "redirects to the latest preview", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App"
        )

      # When
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest")

      # Then
      assert redirected_to(conn) ==
               "/#{project.account.name}/#{project.name}/previews/#{preview.id}"
    end

    test "raises not found error when the project does not exist", %{conn: conn} do
      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, "/account/non-existing-project/previews/latest")
      end
    end

    test "raises not found error when there is no latest preview", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest")
      end
    end

    test "redirects to the latest preview when only non-main branch preview exists", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "feature-branch",
          git_ref: "refs/heads/feature-branch"
        )

      # When
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest")

      # Then
      assert redirected_to(conn) ==
               "/#{project.account.name}/#{project.name}/previews/#{preview.id}"
    end

    test "prefers main branch preview when both main and non-main branch previews exist", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      main_preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "main",
          git_ref: "refs/heads/main",
          inserted_at: ~U[2023-01-02 10:00:00Z]
        )

      _feature_preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_branch: "feature-branch",
          git_ref: "refs/heads/feature-branch",
          inserted_at: ~U[2023-01-01 10:00:00Z]
        )

      # When
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest")

      # Then
      assert redirected_to(conn) ==
               "/#{project.account.name}/#{project.name}/previews/#{main_preview.id}"
    end

    test "filters by bundle-id query parameter when provided", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      _other_preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Other App",
          bundle_identifier: "com.example.other",
          inserted_at: ~U[2023-01-02 10:00:00Z]
        )

      target_preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "Target App",
          bundle_identifier: "com.tuist.dev",
          inserted_at: ~U[2023-01-01 10:00:00Z]
        )

      # When
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest?bundle-id=com.tuist.dev")

      # Then
      assert redirected_to(conn) ==
               "/#{project.account.name}/#{project.name}/previews/#{target_preview.id}"
    end

    test "raises not found error when bundle-id does not match any preview", %{conn: conn, user: user} do
      # Given
      project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        bundle_identifier: "com.example.app"
      )

      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest?bundle-id=com.nonexistent.app")
      end
    end
  end

  describe "download_qr_code_svg/2" do
    test "renders a QR code", %{conn: conn, user: user} do
      # Given
      preview =
        Tuist.Repo.preload(
          AppBuildsFixtures.preview_fixture(project: ProjectsFixtures.project_fixture(account_id: user.account.id)),
          project: :account
        )

      account_name = preview.project.account.name
      project_name = preview.project.name

      expect(QRCode, :create, fn url, _ ->
        assert url == url(~p"/#{account_name}/#{project_name}/previews/#{preview.id}")
        "qr-code"
      end)

      stub(QRCode, :render, fn _ ->
        {:ok, "<svg></svg>"}
      end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/qr-code.svg")

      # Then
      assert response(conn, 200) =~ "<svg"
    end
  end

  describe "download_qr_code_png/2" do
    test "renders a QR code", %{conn: conn} do
      # Given
      preview =
        [type: :ipa]
        |> AppBuildsFixtures.preview_fixture()
        |> Tuist.Repo.preload(project: :account)

      account_name = preview.project.account.name
      project_name = preview.project.name

      stub(QRCode, :create, fn _ ->
        "qr-code"
      end)

      stub(QRCode, :render, fn _, _ ->
        {:ok, "base64png"}
      end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/qr-code.png")

      # Then
      assert response(conn, 200) =~ "base64png"
    end
  end

  describe "download_preview/2" do
    test "redirects to presigned preview download url", %{conn: conn, user: user} do
      # Given
      preview =
        Tuist.Repo.preload(
          AppBuildsFixtures.preview_fixture(project: ProjectsFixtures.project_fixture(account_id: user.account.id)),
          project: :account
        )

      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      account_name = preview.project.account.name
      project_name = preview.project.name

      storage_key =
        AppBuilds.storage_key(%{
          account_handle: account_name,
          project_handle: project_name,
          app_build: app_build
        })

      expect(Storage, :object_exists?, fn ^storage_key, _actor -> true end)

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map(["zip-content"], fn chunk -> chunk end)
      end)

      stub(Zstream, :zip, fn _ -> ["zip-stream"] end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/download")

      # Then
      response = response(conn, :ok)
      assert response == "zip-stream"
    end

    test "returns not found when a preview object is missing", %{conn: conn, user: user} do
      # Given
      preview =
        Tuist.Repo.preload(
          AppBuildsFixtures.preview_fixture(project: ProjectsFixtures.project_fixture(account_id: user.account.id)),
          project: :account
        )

      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      account_name = preview.project.account.name
      project_name = preview.project.name

      storage_key =
        AppBuilds.storage_key(%{
          account_handle: account_name,
          project_handle: project_name,
          app_build: app_build
        })

      expect(Storage, :object_exists?, fn ^storage_key, _actor -> false end)

      # When / Then
      assert_error_sent :not_found, fn ->
        get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/download")
      end
    end
  end

  describe "manifest/2" do
    test "returns manifest.plist", %{conn: conn, user: user} do
      # Given
      preview =
        [
          project: ProjectsFixtures.project_fixture(account_id: user.account.id),
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app"
        ]
        |> AppBuildsFixtures.preview_fixture()
        |> Tuist.Repo.preload(project: :account)

      account_name = preview.project.account.name
      project_name = preview.project.name

      AppBuildsFixtures.app_build_fixture(
        preview: preview,
        type: :ipa
      )

      stub(Storage, :object_exists?, fn _object_key, _actor -> true end)

      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts ->
        "https://storage.tuist.dev/lapse/marquis/previews/build.zip?X-Amz-Signature=abc&X-Amz-Expires=3600"
      end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/manifest.plist")

      # Then
      plist_response = response(conn, 200)

      assert plist_response =~ "<string>dev.tuist.app</string>"
      assert plist_response =~ "<string>1.0.0</string>"

      # The presigned url is embedded directly (no redirect through the server)
      # and XML-escaped so the plist stays valid.
      assert plist_response =~
               "<string>https://storage.tuist.dev/lapse/marquis/previews/build.zip?X-Amz-Signature=abc&amp;X-Amz-Expires=3600</string>"

      refute plist_response =~ "/app.ipa</string>"
    end

    test "raises not found error when the preview does not exist", %{conn: conn, user: user} do
      # Given
      # Create a project so we have a valid account/project path
      project = Tuist.Repo.preload(ProjectsFixtures.project_fixture(account_id: user.account.id), :account)
      account_name = project.account.name
      project_name = project.name

      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, ~p"/#{account_name}/#{project_name}/previews/01911326-4444-771b-8dfa-7d1fc5082eb9/manifest.plist")
      end
    end
  end

  describe "download_archive/2" do
    test "redirects to the presigned archive url when it exists", %{conn: conn, user: user} do
      # Given
      preview =
        [
          project: ProjectsFixtures.project_fixture(account_id: user.account.id),
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app"
        ]
        |> AppBuildsFixtures.preview_fixture()
        |> Tuist.Repo.preload(project: :account)

      account_name = preview.project.account.name
      project_name = preview.project.name

      AppBuildsFixtures.app_build_fixture(
        preview: preview,
        type: :ipa
      )

      presigned_url = "https://storage.tuist.dev/lapse/marquis/previews/build.zip?X-Amz-Signature=abc"

      stub(Storage, :object_exists?, fn _object_key, _actor -> true end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> presigned_url end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/app.ipa")

      # Then
      assert redirected_to(conn) == presigned_url
    end

    test "throws an error when it doesn't exist", %{conn: conn, user: user} do
      # Given
      preview =
        AppBuildsFixtures.preview_fixture(
          project: ProjectsFixtures.project_fixture(account_id: user.account.id),
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app"
        )

      stub(Storage, :object_exists?, fn _object_key, _actor -> false end)

      # When
      assert_error_sent :not_found, fn ->
        get(conn, ~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/app.ipa")
      end
    end
  end

  describe "download_icon/2" do
    test "streams the icon image", %{conn: conn, user: user} do
      # Given
      preview =
        Tuist.Repo.preload(
          AppBuildsFixtures.preview_fixture(project: ProjectsFixtures.project_fixture(account_id: user.account.id)),
          project: :account
        )

      account_name = preview.project.account.name
      project_name = preview.project.name
      icon_content = "icon-content"

      stub(Storage, :object_exists?, fn _object_key, _actor ->
        true
      end)

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map([icon_content], fn chunk -> chunk end)
      end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/icon.png")

      # Then
      assert response(conn, 200) =~ icon_content
      assert get_resp_header(conn, "content-type") == ["image/png"]
    end

    test "returns 404 when the icon does not exist", %{conn: conn} do
      # Given
      preview =
        [type: :ipa]
        |> AppBuildsFixtures.preview_fixture()
        |> Tuist.Repo.preload(project: :account)

      account_name = preview.project.account.name
      project_name = preview.project.name

      stub(Storage, :object_exists?, fn _object_key, _actor ->
        false
      end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/icon.png")

      # Then
      assert response(conn, 404) =~ ""
    end

    test "raises not found error when the preview does not exist", %{conn: conn} do
      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, ~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9/icon.png")
      end
    end
  end

  describe "access to private previews" do
    setup do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      preview =
        [project: project, bundle_identifier: "dev.tuist.app", version: "1.0.0"]
        |> AppBuildsFixtures.preview_fixture()
        |> Tuist.Repo.preload(project: :account)

      AppBuildsFixtures.app_build_fixture(preview: preview, type: :ipa)

      stub(Storage, :object_exists?, fn _object_key, _actor -> true end)

      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts ->
        "https://storage.tuist.dev/previews/build.zip?X-Amz-Signature=abc"
      end)

      %{project: project, preview: preview, base_path: "/#{project.account.name}/#{project.name}/previews"}
    end

    test "latest redirects signed-out visitors to log in instead of revealing the preview", %{base_path: base_path} do
      conn = get(build_conn(), "#{base_path}/latest")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "latest raises not found for signed-in users who cannot read the project", %{conn: conn, base_path: base_path} do
      assert_raise NotFoundError, fn ->
        get(conn, "#{base_path}/latest")
      end
    end

    test "latest redirects signed-out visitors to a public preview", %{project: project, base_path: base_path} do
      preview =
        AppBuildsFixtures.preview_fixture(project: project, visibility: :public, bundle_identifier: "dev.tuist.public")

      conn = get(build_conn(), "#{base_path}/latest?bundle-id=dev.tuist.public")

      assert redirected_to(conn) == "#{base_path}/#{preview.id}"
    end

    test "manifest redirects signed-out visitors without an install token to log in", %{
      preview: preview,
      base_path: base_path
    } do
      conn = get(build_conn(), "#{base_path}/#{preview.id}/manifest.plist")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "manifest is served to signed-out visitors with a valid install token", %{
      preview: preview,
      base_path: base_path
    } do
      token = AppBuilds.preview_install_token(preview)

      conn = get(build_conn(), "#{base_path}/#{preview.id}/manifest.plist?token=#{token}")

      assert response(conn, 200) =~ "https://storage.tuist.dev/previews/build.zip?X-Amz-Signature=abc"
    end

    test "manifest rejects an install token issued for another preview", %{
      project: project,
      preview: preview,
      base_path: base_path
    } do
      other_preview = AppBuildsFixtures.preview_fixture(project: project)
      token = AppBuilds.preview_install_token(other_preview)

      conn = get(build_conn(), "#{base_path}/#{preview.id}/manifest.plist?token=#{token}")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "manifest raises not found for signed-in users who cannot read the project", %{
      conn: conn,
      preview: preview,
      base_path: base_path
    } do
      assert_raise NotFoundError, fn ->
        get(conn, "#{base_path}/#{preview.id}/manifest.plist")
      end
    end

    test "manifest is served without a token for public previews", %{project: project, base_path: base_path} do
      preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :public)
      AppBuildsFixtures.app_build_fixture(preview: preview, type: :ipa)

      conn = get(build_conn(), "#{base_path}/#{preview.id}/manifest.plist")

      assert response(conn, 200) =~ "https://storage.tuist.dev/previews/build.zip?X-Amz-Signature=abc"
    end

    test "app.ipa redirects signed-out visitors without an install token to log in", %{
      preview: preview,
      base_path: base_path
    } do
      conn = get(build_conn(), "#{base_path}/#{preview.id}/app.ipa")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "app.apk redirects to the archive with a valid install token", %{project: project, base_path: base_path} do
      preview = AppBuildsFixtures.preview_fixture(project: project)
      AppBuildsFixtures.app_build_fixture(preview: preview, type: :apk)
      token = AppBuilds.preview_install_token(preview)

      conn = get(build_conn(), "#{base_path}/#{preview.id}/app.apk?token=#{token}")

      assert redirected_to(conn, 302) == "https://storage.tuist.dev/previews/build.zip?X-Amz-Signature=abc"
    end

    test "download raises not found for signed-in users who cannot read the project", %{
      conn: conn,
      preview: preview,
      base_path: base_path
    } do
      assert_raise NotFoundError, fn ->
        get(conn, "#{base_path}/#{preview.id}/download")
      end
    end

    test "install endpoints raise not found for a preview of another project", %{conn: conn, user: user, preview: preview} do
      own_project = ProjectsFixtures.project_fixture(account_id: user.account.id, preload: [:account])

      assert_raise NotFoundError, fn ->
        get(conn, "/#{own_project.account.name}/#{own_project.name}/previews/#{preview.id}/manifest.plist")
      end
    end

    test "preview page raises not found for a preview of another project", %{conn: conn, user: user, preview: preview} do
      own_project =
        ProjectsFixtures.project_fixture(account_id: user.account.id, visibility: :public, preload: [:account])

      assert_raise NotFoundError, fn ->
        get(conn, "/#{own_project.account.name}/#{own_project.name}/previews/#{preview.id}")
      end
    end
  end
end
