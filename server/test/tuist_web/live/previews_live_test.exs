defmodule TuistWeb.PreviewsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistWeb.Previews.AppPreview

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

  test "release notes summaries ignore blank notes and normalize line endings" do
    for notes <- [nil, "", " \t\n\r\n"] do
      assert AppPreview.release_notes_summary(notes) == nil
    end

    for newline <- ["\n", "\r\n", "\r", "\u2028"] do
      assert AppPreview.release_notes_summary(" \n Build 204  " <> newline <> "Detailed instructions") == "Build 204"
    end
  end

  test "shows only the first release notes line as escaped text in cards and rows", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    first_line = "Build 204 <script>alert('test')</script> **QA**"
    notes = first_line <> "\r\nDetailed QA instructions belong on the preview detail page"

    preview =
      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "Atlas",
        track: "QA",
        release_notes: notes,
        supported_platforms: [:ios]
      )

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")

    assert has_element?(lv, "[data-part='latest-app-previews'] .tuist-app-preview", "Atlas")
    assert has_element?(lv, "#previews-table", "Atlas")
    assert has_element?(lv, "#previews-table td:nth-child(3) [data-part='label']", "Qa")
    assert has_element?(lv, "#previews-table [data-part='row-link'][href$='/previews/#{preview.id}']")
    assert has_element?(lv, ".tuist-app-preview [data-part='release-notes-summary']", first_line)
    assert has_element?(lv, "#previews-table [data-part='description']", first_line)
    refute html =~ "Detailed QA instructions belong on the preview detail page"
    refute has_element?(lv, ".tuist-app-preview script")
    refute has_element?(lv, "#previews-table script")
    refute has_element?(lv, "#previews-table strong")
    refute has_element?(lv, "[data-part='release-notes']")
  end

  test "omits release notes snippets when notes are absent", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    AppBuildsFixtures.preview_fixture(project: project, release_notes: nil)
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")
    refute has_element?(lv, "[data-part='release-notes-summary']")
    refute has_element?(lv, "#previews-table [data-part='description']")
  end

  test "searches full release notes and preserves word search across names and notes", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    AppBuildsFixtures.preview_fixture(
      project: project,
      display_name: "Atlas",
      track: "QA",
      release_notes: "Build 204\nFix CHECKOUT for 100%_ready testers"
    )

    AppBuildsFixtures.preview_fixture(project: project, display_name: "Atlas", track: "QA")
    AppBuildsFixtures.preview_fixture(display_name: "Atlas", release_notes: "checkout")

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/previews")
    lv |> form("form[phx-change='search-name']", %{name: "checkout Atlas"}) |> render_change()

    assert has_element?(lv, "#previews-table [data-part='description']", "Build 204")

    assert lv |> element("#previews-table") |> render() |> Floki.parse_fragment!() |> Floki.find("tbody tr") |> length() ==
             1

    refute has_element?(lv, "#previews-table", "Fix CHECKOUT")

    lv |> form("form[phx-change='search-name']", %{name: "%_"}) |> render_change()
    assert has_element?(lv, "#previews-table [data-part='description']", "Build 204")

    assert lv |> element("#previews-table") |> render() |> Floki.parse_fragment!() |> Floki.find("tbody tr") |> length() ==
             1
  end

  test "ignores a stale pagination cursor on initial load", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    AppBuildsFixtures.preview_fixture(
      project: project,
      display_name: "AppOne",
      supported_platforms: [:ios]
    )

    stale_cursor =
      "g3QAAAABdxFpbnNlcnRlZF9hdF9uYWl2ZXQAAAAJdwttaWNyb3NlY29uZGgCYQBhAHcGc2Vjb25kYRF3CGNhbGVuZGFydxNFbGl4aXIuQ2FsZW5kYXIuSVNPdwVtb250aGEEdwpfX3N0cnVjdF9fdxRFbGl4aXIuTmFpdmVEYXRlVGltZXcEeWVhcmIAAAfpdwZtaW51dGVhHncEaG91cmEMdwNkYXlhDg=="

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/previews?before=#{stale_cursor}"
      )

    assert has_element?(lv, "#previews-table span", "AppOne")
  end

  test "preserves a matching pagination cursor on initial load", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    matching_cursor = Flop.Cursor.encode(%{inserted_at: ~N[2025-04-14 12:30:17]})

    stub(Tuist.AppBuilds, :latest_previews_with_distinct_bundle_ids, fn _ -> [] end)

    stub(Tuist.AppBuilds, :list_previews, fn attrs, _opts ->
      assert attrs[:after] == matching_cursor

      {[],
       %Flop.Meta{
         has_previous_page?: false,
         has_next_page?: false,
         start_cursor: nil,
         end_cursor: nil
       }}
    end)

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/previews?after=#{matching_cursor}"
      )

    assert has_element?(lv, ".tuist-empty-state")
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
