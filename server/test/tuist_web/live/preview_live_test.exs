defmodule TuistWeb.PreviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.AppBuilds
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

  setup %{project: project} do
    preview = AppBuildsFixtures.preview_fixture(project: project)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    %{preview: preview}
  end

  test "renders release notes as escaped plain text", %{conn: conn, organization: organization, project: project} do
    notes = "Fix sign-in\n<script>alert('test')</script>"
    preview = AppBuildsFixtures.preview_fixture(project: project, release_notes: notes)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    assert has_element?(lv, "[data-part='release-notes-card']", "Fix sign-in")
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>alert"
  end

  test "omits release notes when none were uploaded", %{
    conn: conn,
    organization: organization,
    project: project,
    preview: preview
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")
    refute has_element?(lv, "[data-part='release-notes-card']")
  end

  test "lets the preview page be embedded in an iframe on another site", %{
    conn: conn,
    organization: organization,
    project: project,
    preview: preview
  } do
    # When
    conn = get(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors *;"
  end

  test "keeps the previews list out of iframes on other sites", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    conn = get(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'self';"
  end

  test "renders none as a commit when git_commit_sha",
       %{
         conn: conn,
         organization: organization,
         project: project
       } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(git_commit_sha: nil, project: project)

    app_build =
      AppBuildsFixtures.app_build_fixture(preview: preview, supported_platforms: [:ios, :macos])

    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "div[data-part='metadata'] span[data-part='label']", "None")
  end

  for {platform, type} <- [{:macos, :executable}, {:linux, :executable}, {:macos, :app_bundle}] do
    @platform platform
    @build_type type
    test "shows CLI instructions for a desktop #{type} preview on #{platform}", %{conn: conn, project: project} do
      preview =
        AppBuildsFixtures.preview_fixture(project: project, display_name: "tuist", version: nil, bundle_identifier: nil)

      build = AppBuildsFixtures.app_build_fixture(preview: preview, type: @build_type, supported_platforms: [@platform])
      AppBuilds.update_preview_with_app_build(preview.id, build)

      {:ok, view, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/previews/#{preview.id}")

      assert has_element?(view, "[data-part='install-app-card']", "Run preview")
      assert has_element?(view, "[data-part='install-app-card'] .tuist-terminal", "tuist run")
      assert has_element?(view, "#desktop-preview-trust-alert", "not sandboxed")
      refute has_element?(view, "#preview-run-button")
      refute has_element?(view, "#download-tuist-app-alert")
      refute has_element?(view, "[data-part='device-not-available']")
      refute has_element?(view, "[data-part='version']")

      if @build_type == :executable do
        assert has_element?(view, "[data-part='preview-type']", "CLI")
        assert has_element?(view, "img[src='/app/images/cli-icon.svg'][alt='Command-line preview']")
        refute has_element?(view, "#preview-header-icon")
      else
        refute has_element?(view, "[data-part='preview-type']", "CLI")
        assert has_element?(view, "#preview-header-icon[phx-hook='ImageFallback']")
      end
    end
  end

  test "it shows supported platforms", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(project: project)

    app_build =
      AppBuildsFixtures.app_build_fixture(preview: preview, supported_platforms: [:ios, :macos])

    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, ".noora-tag span", "iOS")
    assert has_element?(lv, ".noora-tag span", "macOS")
  end

  test "it does not show run button when family is iOS and preview_type is :app_bundle",
       %{
         conn: conn,
         organization: organization,
         project: project
       } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(project: project)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview, type: :app_bundle)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    stub(UAParser, :parse, fn _ -> %UAParser.UA{os: %UAParser.OperatingSystem{family: "iOS"}} end)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "#preview-run-button span", "Run")
  end

  test "it shows run button when family is iOS", %{
    conn: conn,
    organization: organization,
    project: project,
    preview: preview
  } do
    # Given
    stub(UAParser, :parse, fn _ ->
      %UAParser.UA{os: %UAParser.OperatingSystem{family: "macOS"}}
    end)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "#preview-run-button span", "Run")
  end

  test "it shows run button for android preview on macOS", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(project: project, supported_platforms: [:android])

    app_build =
      AppBuildsFixtures.app_build_fixture(
        preview: preview,
        type: :apk,
        supported_platforms: [:android]
      )

    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    stub(UAParser, :parse, fn _ ->
      %UAParser.UA{os: %UAParser.OperatingSystem{family: "macOS"}}
    end)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "#preview-run-button span", "Run")
  end

  test "it requires authenticated user when the preview is :app_bundle", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    Authentication.log_out_user(conn)
    preview = AppBuildsFixtures.preview_fixture(git_commit_sha: nil, project: project)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview, type: :app_bundle)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    got = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert got == {:error, {:redirect, %{to: "/users/log_in", flash: %{}}}}
  end

  test "it does not require authenticated user when the preview is :public", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    Authentication.log_out_user(conn)
    preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :public)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview, type: :ipa)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "#preview-run-button span", "Run")
  end

  test "it hides delete button for public preview when logged out", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    Authentication.log_out_user(conn)
    preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :public)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview, type: :ipa)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "button[data-part='delete-button']")
  end

  test "it allows members to delete previews", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(project: project)
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # When
    lv |> element("button[data-part='delete-button']") |> render_click()

    # Then
    assert_redirect(lv, ~p"/#{organization.account.name}/#{project.name}/previews")
    assert {:error, :not_found} = AppBuilds.preview_by_id(preview.id)
  end

  test "raises not found error when the preview does not exist", %{conn: conn} do
    # When / Then
    assert_raise NotFoundError, fn ->
      get(conn, ~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9")
    end
  end

  test "raises not found error when the preview is not accessible by the current user", %{
    conn: conn
  } do
    # Given
    preview =
      AppBuildsFixtures.app_build_fixture()

    # When / Then
    assert_raise NotFoundError, fn ->
      get(conn, ~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}")
    end
  end

  test "shows track when set", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(project: project, track: "beta")
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "div[data-part='title']", "Track")
    assert has_element?(lv, "div[data-part='metadata'] span[data-part='label']", "beta")
  end

  test "does not show track row when track is empty", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = AppBuildsFixtures.preview_fixture(project: project, track: "")
    app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
    AppBuilds.update_preview_with_app_build(preview.id, app_build)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "div[data-part='title']", "Track")
  end
end
