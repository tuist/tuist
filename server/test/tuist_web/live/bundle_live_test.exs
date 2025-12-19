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

  describe "file breakdown type filter" do
    test "shows the filter dropdown on file breakdown tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          artifacts: [
            %{
              artifact_type: :asset,
              path: "App.app/image.png",
              size: 100,
              shasum: "abc123"
            },
            %{
              artifact_type: :binary,
              path: "App.app/App",
              size: 200,
              shasum: "def456"
            }
          ]
        )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=file-breakdown")

      # Then
      assert has_element?(lv, "#file-breakdown-filter-dropdown")
    end

    test "filters file breakdown by artifact type", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 300,
          artifacts: [
            %{
              artifact_type: :asset,
              path: "App.app/image.png",
              size: 100,
              shasum: "abc123"
            },
            %{
              artifact_type: :binary,
              path: "App.app/AppBinary",
              size: 200,
              shasum: "def456"
            }
          ]
        )

      # When - filter by asset type using the Noora.Filter query format
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=file-breakdown&filter_artifact_type_op===&filter_artifact_type_val=asset"
        )

      # Then - only asset artifact should be shown
      assert has_element?(lv, "#file-breakdown-table")
      html = render(lv)
      assert html =~ "image.png"
      refute html =~ "AppBinary"
    end

    test "shows all types when no filter is applied", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 300,
          artifacts: [
            %{
              artifact_type: :asset,
              path: "App.app/image.png",
              size: 100,
              shasum: "abc123"
            },
            %{
              artifact_type: :binary,
              path: "App.app/AppBinary",
              size: 200,
              shasum: "def456"
            }
          ]
        )

      # When - no type filter
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=file-breakdown")

      # Then - both artifacts should be shown
      html = render(lv)
      assert html =~ "image.png"
      assert html =~ "AppBinary"
    end
  end
end
