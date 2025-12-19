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
