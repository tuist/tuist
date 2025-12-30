defmodule TuistWeb.PreviewsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AppBuildsFixtures

  test "renders empty view when no previews are available", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert has_element?(lv, ".tuist-empty-state")
  end

  test "lists latest share previews", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_one =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "AppOne",
        supported_platforms: [:ios]
      )

    _preview_two =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "AppTwo",
        supported_platforms: []
      )

    _preview_three =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert has_element?(lv, "span", "AppOne")
    assert has_element?(lv, "span", "AppTwo")
  end

  test "lists previews when a preview has no git metadata", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_one =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "AppOne",
        supported_platforms: [:ios],
        git_branch: nil,
        git_commit_sha: nil
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert has_element?(lv, "span", "AppOne")
  end

  test "displays track column with None when track is not set", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "AppOne",
        supported_platforms: [:ios]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert has_element?(lv, "#previews-table td:nth-child(3) [data-part='label']", "None")
  end

  test "displays track column with track value when set", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "AppOne",
        supported_platforms: [:ios],
        track: "beta"
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert has_element?(lv, "#previews-table td:nth-child(3) [data-part='label']", "Beta")
  end

  test "filters previews by name using search field", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_one =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "MyApp",
        supported_platforms: [:ios]
      )

    _preview_two =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "OtherApp",
        supported_platforms: [:ios]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews?name=MyApp")

    # Then
    assert has_element?(lv, "#previews-table span", "MyApp")
    refute has_element?(lv, "#previews-table span", "OtherApp")
  end

  test "filters previews by track using filter dropdown", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_beta =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "BetaApp",
        supported_platforms: [:ios],
        track: "beta"
      )

    _preview_nightly =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "NightlyApp",
        supported_platforms: [:ios],
        track: "nightly"
      )

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews?filter_track_op==~&filter_track_val=beta")

    # Then
    assert has_element?(lv, "#previews-table span", "BetaApp")
    refute has_element?(lv, "#previews-table span", "NightlyApp")
  end

  test "filters previews by track case insensitively", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_beta =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "BetaApp",
        supported_platforms: [:ios],
        track: "beta"
      )

    _preview_nightly =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "NightlyApp",
        supported_platforms: [:ios],
        track: "nightly"
      )

    # When - filter with uppercase BETA
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews?filter_track_op==~&filter_track_val=BETA")

    # Then - should still find the beta track preview
    assert has_element?(lv, "#previews-table span", "BetaApp")
    refute has_element?(lv, "#previews-table span", "NightlyApp")
  end

  test "filters previews by branch using filter dropdown", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_main =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "MainApp",
        supported_platforms: [:ios],
        git_branch: "main"
      )

    _preview_feature =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "FeatureApp",
        supported_platforms: [:ios],
        git_branch: "feature/test"
      )

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/previews?filter_branch_op==~&filter_branch_val=feature")

    # Then
    assert has_element?(lv, "#previews-table span", "FeatureApp")
    refute has_element?(lv, "#previews-table span", "MainApp")
  end
end
