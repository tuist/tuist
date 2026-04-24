defmodule TuistWeb.BundleLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistWeb.Errors.NotFoundError

  test "it shows bundle metadata", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    bundle = BundlesFixtures.bundle_fixture(project: project)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

    # Then
    assert has_element?(lv, "span[data-part='label']", "main")
  end

  test "raises not found error when the bundle does not exist", %{conn: conn} do
    # When / Then
    assert_raise NotFoundError, fn ->
      get(conn, ~p"/tuist/ios_app_with_frameworks/bundles/01911326-4444-771b-8dfa-7d1fc5082eb9")
    end
  end

  test "raises not found error when the bundle is not accessible by the current user", %{
    conn: conn
  } do
    # Given
    bundle =
      BundlesFixtures.bundle_fixture()

    # When / Then
    assert_raise NotFoundError, fn ->
      get(conn, ~p"/tuist/ios_app_with_frameworks/bundles/#{bundle.id}")
    end
  end

  test "falls back to the first page when the bundle-size-analysis-table-page query param is not an integer",
       %{
         conn: conn,
         organization: organization,
         project: project
       } do
    # Given
    bundle = BundlesFixtures.bundle_fixture(project: project)
    path_hash = :md5 |> :crypto.hash("App.app") |> Base.encode16() |> String.slice(0, 8)
    page_param = "bundle-size-analysis-table-page-#{path_hash}"

    # When
    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?#{[{page_param, "not-an-integer"}]}"
      )

    # Then
    assert has_element?(lv, "span[data-part='label']", "main")
  end
end
