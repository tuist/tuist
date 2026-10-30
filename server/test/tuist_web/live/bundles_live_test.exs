defmodule TuistWeb.BundlesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.BundlesFixtures

  @render_async_timeout 1_000

  test "renders empty view when no bundles are available", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    # Then
    assert has_element?(lv, ".tuist-empty-state")
  end

  test "lists latest bundles", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given — two bundles of the same app, so both fall under the page's
    # app-name filter (defaulted from the first app with :ios platform).
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "App",
      git_commit_sha: "aaaa111bbbb",
      inserted_at: DateTime.add(DateTime.utc_now(), -1, :hour)
    )

    BundlesFixtures.bundle_fixture(
      project: project,
      name: "App",
      git_commit_sha: "cccc222dddd"
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    # Then
    assert has_element?(lv, "#bundles-table span", "aaaa111")
    assert has_element?(lv, "#bundles-table span", "cccc222")
  end

  test "shows flavor tags and filters by exact tag membership", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    BundlesFixtures.bundle_fixture(
      project: project,
      custom_tags: ["paid", "release", "nightly"],
      git_commit_sha: "aaaa111"
    )

    BundlesFixtures.bundle_fixture(project: project, custom_tags: ["paid-extra"], git_commit_sha: "bbbb222")
    BundlesFixtures.bundle_fixture(project: project, git_commit_sha: "cccc333")
    BundlesFixtures.bundle_fixture(custom_tags: ["other-project"])

    path = ~p"/#{organization.account.name}/#{project.name}/bundles"
    {:ok, lv, _html} = live(conn, path)

    assert has_element?(lv, "#bundles-table", "paid")
    assert has_element?(lv, "#bundles-table", "+1")
    refute has_element?(lv, "#filter-dropdown", "other-project")

    render_click(lv, "add_filter", %{"value" => "custom_tags"})

    lv
    |> element("#filter-custom_tags-value-popover form")
    |> render_submit(%{"type" => "change_value", "payload_filter_id" => "custom_tags", "value" => "paid"})

    assert has_element?(lv, "#bundles-table span", "aaaa111")
    refute has_element?(lv, "#bundles-table span", "bbbb222")
    refute has_element?(lv, "#bundles-table span", "cccc333")

    render_patch(
      lv,
      path <> "?" <> URI.encode_query(%{"filter_custom_tags_op" => "!=~", "filter_custom_tags_val" => "paid"})
    )

    refute has_element?(lv, "#bundles-table span", "aaaa111")
    assert has_element?(lv, "#bundles-table span", "bbbb222")
    assert has_element?(lv, "#bundles-table span", "cccc333")

    render_patch(
      lv,
      path <> "?" <> URI.encode_query(%{"filter_custom_tags_op" => "=~", "filter_custom_tags_val" => "missing"})
    )

    refute has_element?(lv, "#bundles-table span", "aaaa111")
    refute has_element?(lv, "#bundles-table span", "bbbb222")
    refute has_element?(lv, "#bundles-table span", "cccc333")
  end

  test "rejects invalid tag filters instead of silently broadening results", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    BundlesFixtures.bundle_fixture(project: project)
    path = ~p"/#{organization.account.name}/#{project.name}/bundles"

    for {operator, tag} <- [{"=~", " "}, {"=~", String.duplicate("a", 51)}, {">", "paid"}] do
      query = URI.encode_query(%{"filter_custom_tags_op" => operator, "filter_custom_tags_val" => tag})

      assert_raise TuistWeb.Errors.BadRequestError, fn ->
        live(conn, path <> "?" <> query)
      end
    end
  end

  test "defaults download size to 0 MB when last bundle has only install size", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "AppOne",
      install_size: 1000,
      download_size: nil
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "span", "0 MB")
  end

  test "shows branch dropdown when there are bundles in main branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "AppOne",
      git_branch: "main"
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    # Then
    assert has_element?(lv, "#bundle-size-branch-dropdown")
    assert has_element?(lv, "span", "Branch:")
  end

  test "hides branch dropdown when there are no bundles in main branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "AppOne",
      git_branch: "feature/some-branch"
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    # Then
    refute has_element?(lv, "#bundle-size-branch-dropdown")
  end

  test "filters bundle data by main branch when main is selected", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given - create bundles in different branches
    _main_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "AppOne",
        git_branch: "main",
        install_size: 2000
      )

    _feature_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "AppOne",
        git_branch: "feature/test",
        install_size: 3000
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles?bundle-size-branch=main")

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "span", "2.0 KB")
  end

  test "includes all branches when any is selected", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    _main_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "AppOne",
        git_branch: "main",
        install_size: 2000,
        inserted_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      )

    _feature_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "AppOne",
        git_branch: "feature/test",
        install_size: 3000,
        inserted_at: DateTime.utc_now()
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles?bundle-size-branch=any")

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "span", "3.0 KB")
  end

  test "defaults to any branch when no bundles exist in main branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given - create bundle only in feature branch, not in main
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "AppOne",
      git_branch: "feature/test",
      install_size: 5000
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    render_async(lv, @render_async_timeout)

    # Then - should show data from feature branch since no main branch bundles exist
    assert has_element?(lv, "span", "5.0 KB")
    # Dropdown should be hidden since no main branch bundles
    refute has_element?(lv, "#bundle-size-branch-dropdown")
  end

  test "shows no change when previous bundle download_size is nil", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _previous_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TestApp",
        install_size: 1000,
        download_size: nil,
        inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)
      )

    _last_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TestApp",
        install_size: 1500,
        download_size: 1000,
        inserted_at: DateTime.utc_now()
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "#widget-download-size span", "No change")
  end

  test "shows no change when last bundle download_size is 0", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _previous_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TestApp",
        install_size: 1000,
        download_size: 500,
        inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)
      )

    _last_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TestApp",
        install_size: 1500,
        download_size: 0,
        inserted_at: DateTime.utc_now()
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "#widget-download-size span", "No change")
  end

  test "shows a 100.0% trend when previous bundle download_size is 0", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _previous_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TestApp",
        install_size: 1000,
        download_size: 0,
        inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)
      )

    _last_bundle =
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "TestApp",
        install_size: 1500,
        download_size: 1000,
        inserted_at: DateTime.utc_now()
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    render_async(lv, @render_async_timeout)

    # Then
    assert has_element?(lv, "#widget-download-size span", "+100.0%")
  end

  test "handles cursor mismatch when sort order changes", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Use a single app name so all bundles match the page's app-name filter.
    for i <- 1..25 do
      BundlesFixtures.bundle_fixture(
        project: project,
        name: "App",
        install_size: i * 1024
      )
    end

    # Generate a cursor with inserted_at sorting
    {_bundles, %{end_cursor: cursor}} =
      Tuist.Bundles.list_bundles(%{
        filters: [%{field: :project_id, op: :==, value: project.id}],
        order_by: [:inserted_at],
        order_directions: [:desc],
        first: 20
      })

    # Navigate with install_size sorting but use the cursor from inserted_at sorting
    # Before the fix, this would raise Flop.InvalidParamsError
    assert {:ok, lv, _html} =
             live(
               conn,
               ~p"/#{organization.account.name}/#{project.name}/bundles?bundles-sort-by=install-size&bundles-sort-order=asc&after=#{cursor}"
             )

    # install_size ascending starts at 1024 bytes = "1.0 KB".
    assert has_element?(lv, "#bundles-table span", "1.0 KB")
  end
end
