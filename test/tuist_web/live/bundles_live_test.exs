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
    # Given
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "AppOne"
    )

    BundlesFixtures.bundle_fixture(
      project: project,
      name: "AppTwo"
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles")

    # Then
    assert has_element?(lv, "span", "AppOne")
    assert has_element?(lv, "span", "AppTwo")
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
end
