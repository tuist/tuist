defmodule TuistWeb.BundlesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.BundlesFixtures

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

    # Then - should show data from feature branch since no main branch bundles exist
    assert has_element?(lv, "span", "5.0 KB")
    # Dropdown should be hidden since no main branch bundles
    refute has_element?(lv, "#bundle-size-branch-dropdown")
  end

  test "defaults to 0.0% download size trend when previous bundle download_size is nil", %{
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

    # Then
    assert has_element?(lv, "#widget-download-size span", "0.0%")
  end

  test "download size is 0.0% when last bundle download_size is 0", %{
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

    # Then
    assert has_element?(lv, "#widget-download-size span", "0.0%")
  end

  test "download is 0.0% when previous bundle download_size is 0", %{
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

    # Then
    assert has_element?(lv, "#widget-download-size span", "0.0%")
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
