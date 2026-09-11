defmodule TuistWeb.BundleLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Utilities.ByteFormatter
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
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

  test "raises not found when a bundle belongs to a different project", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    other_project = ProjectsFixtures.project_fixture()
    bundle = BundlesFixtures.bundle_fixture(project: other_project)

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")
    end
  end

  test "does not expose deletion controls to anonymous readers of a public project", %{} do
    project = ProjectsFixtures.project_fixture(visibility: :public)
    project = Tuist.Repo.preload(project, :account)
    bundle = BundlesFixtures.bundle_fixture(project: project)

    {:ok, live_view, _html} = live(build_conn(), ~p"/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

    refute has_element?(live_view, "[data-part='delete-button']")
    render_hook(live_view, "delete_bundle", %{})
    assert {:ok, _bundle} = Tuist.Bundles.get_bundle(bundle.id, project_id: project.id)
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

  describe "duplicate insights" do
    test "renders only the first page of duplicate groups", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_duplicates(project, groups: 25, artifacts_per_group: 2)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      assert duplicate_group_count(lv) == 20
      assert has_element?(lv, ".noora-pagination-group a[data-part='page-button'][href='?duplicates-page=2']")
    end

    test "renders the remaining duplicate groups on the second page", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_duplicates(project, groups: 25, artifacts_per_group: 2)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # When
      lv |> element(".noora-pagination-group a[data-part='page-button'][href='?duplicates-page=2']") |> render_click()

      # Then
      assert duplicate_group_count(lv) == 5
    end

    test "keeps the potential savings total across every duplicate group", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_duplicates(project, groups: 25, artifacts_per_group: 2)

      total_size =
        bundle.id
        |> Tuist.Bundles.get_bundle_artifact_tree()
        |> Enum.filter(&String.starts_with?(&1.shasum, "duplicate-"))
        |> Enum.reduce(0, &(&1.size + &2))

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      assert has_element?(lv, "[data-part='savings-value']", ByteFormatter.format_bytes(total_size))
    end

    test "keeps the section expanded while paging through the groups", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_duplicates(project, groups: 25, artifacts_per_group: 2)
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")
      render_hook(lv, "duplicates_open_changed", %{"open" => true})

      # When
      lv
      |> element(".noora-pagination-group a[data-part='page-button'][href='?duplicates-page=2']")
      |> render_click()

      # Then
      assert has_element?(lv, "#insights-duplicates [data-part='content'][data-state='open']")
    end

    test "caps the artifacts listed inside a single duplicate group", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_duplicates(project, groups: 1, artifacts_per_group: 25)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      assert lv |> render() |> Floki.parse_document!() |> Floki.find("[data-part='duplicate']") |> length() == 21
      assert has_element?(lv, "[data-part='duplicate'] [data-part='title']", "and 5 more")
      assert has_element?(lv, "[data-part='trigger'] [data-part='header'] .noora-badge", "25 duplicates")
    end
  end

  defp bundle_with_duplicates(project, opts) do
    groups = Keyword.fetch!(opts, :groups)
    artifacts_per_group = Keyword.fetch!(opts, :artifacts_per_group)

    files =
      for group <- 1..groups, copy <- 1..artifacts_per_group do
        %{
          artifact_type: :asset,
          path: "App.app/Module#{copy}/asset_#{group}.png",
          size: 1024 * group,
          shasum: "duplicate-#{group}",
          children: []
        }
      end

    install_size = Enum.reduce(files, 0, &(&1.size + &2))

    BundlesFixtures.bundle_fixture(
      project: project,
      install_size: install_size,
      artifacts: [
        %{
          artifact_type: :directory,
          path: "App.app",
          size: install_size,
          shasum: "app",
          children: files
        }
      ]
    )
  end

  defp duplicate_group_count(lv) do
    lv
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[id$='-insights-duplicate-collapsible']")
    |> length()
  end
end
