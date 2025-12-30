defmodule TuistWeb.PreviewControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

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
    test "redirects to the latest badge", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

      # When
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest/badge.svg")

      # Then
      assert redirected_to(conn) == ~p"/app/images/previews-badge.svg"
    end
  end

  describe "latest/2" do
    test "redirects to the latest preview", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

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

    test "raises not found error when there is no latest preview", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, ~p"/#{project.account.name}/#{project.name}/previews/latest")
      end
    end

    test "redirects to the latest preview when only non-main branch preview exists", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

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

    test "prefers main branch preview when both main and non-main branch previews exist", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

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

    test "filters by bundle-id query parameter when provided", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

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

    test "raises not found error when bundle-id does not match any preview", %{conn: conn} do
      # Given
      project =
        ProjectsFixtures.project_fixture(preload: [:account])

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
    test "renders a QR code", %{conn: conn} do
      # Given
      preview = Tuist.Repo.preload(AppBuildsFixtures.preview_fixture(), project: :account)

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
    test "redirects to presigned preview download url", %{conn: conn} do
      # Given
      preview = Tuist.Repo.preload(AppBuildsFixtures.preview_fixture(), project: :account)

      account_name = preview.project.account.name
      project_name = preview.project.name

      stub(Zstream, :zip, fn _ -> ["zip-stream"] end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/download")

      # Then
      response = response(conn, :ok)
      assert response == "zip-stream"
    end
  end

  describe "manifest/2" do
    test "returns manifest.plist", %{conn: conn} do
      # Given
      preview =
        [
          project: ProjectsFixtures.project_fixture(),
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

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/manifest.plist")

      # Then
      plist_response = response(conn, 200)

      assert plist_response =~ "<string>dev.tuist.app</string>"
      assert plist_response =~ "<string>1.0.0</string>"
    end

    test "raises not found error when the preview does not exist", %{conn: conn} do
      # Given
      # Create a project so we have a valid account/project path
      project = Tuist.Repo.preload(ProjectsFixtures.project_fixture(), :account)
      account_name = project.account.name
      project_name = project.name

      # When / Then
      assert_raise NotFoundError, fn ->
        get(conn, ~p"/#{account_name}/#{project_name}/previews/01911326-4444-771b-8dfa-7d1fc5082eb9/manifest.plist")
      end
    end
  end

  describe "download_archive/2" do
    test "returns archive object when it exists", %{conn: conn} do
      # Given
      preview =
        [
          project: ProjectsFixtures.project_fixture(),
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
      stub(Storage, :get_object_as_string, fn _object_key, _actor -> "ipa-contents" end)

      # When
      conn = get(conn, ~p"/#{account_name}/#{project_name}/previews/#{preview.id}/app.ipa")

      # Then
      assert response(conn, 200) =~ "ipa-contents"
    end

    test "throws an error when it doesn't exist", %{conn: conn} do
      # Given
      preview =
        AppBuildsFixtures.preview_fixture(
          project: ProjectsFixtures.project_fixture(),
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
    test "streams the icon image", %{conn: conn} do
      # Given
      preview = Tuist.Repo.preload(AppBuildsFixtures.preview_fixture(), project: :account)

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
end
