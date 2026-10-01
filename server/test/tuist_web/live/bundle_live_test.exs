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

  describe "build_tree_data/2" do
    test "marks the chart nodes whose shasum is duplicated" do
      artifacts = [
        %{
          id: "app",
          artifact_id: nil,
          artifact_type: :directory,
          path: "App.app",
          size: 3,
          shasum: "app",
          children: [
            %{
              id: "a",
              artifact_id: "app",
              artifact_type: :asset,
              path: "App.app/a.png",
              size: 1,
              shasum: "duplicate",
              collapsed?: false,
              children: []
            },
            %{
              id: "b",
              artifact_id: "app",
              artifact_type: :asset,
              path: "App.app/b.png",
              size: 2,
              shasum: "unique",
              collapsed?: false,
              children: []
            }
          ]
        }
      ]

      [%{children: children}] = TuistWeb.BundleLive.build_tree_data(artifacts, MapSet.new(["duplicate"]))

      assert %{"a.png" => true, "b.png" => false} == Map.new(children, &{&1.name, &1.duplicate?})
    end

    test "keeps the child's path when merging a directory with a single child" do
      artifacts = [
        %{
          id: "app",
          artifact_id: nil,
          artifact_type: :directory,
          path: "App.app",
          size: 3,
          shasum: "app",
          children: [
            %{
              id: "bundle",
              artifact_id: "app",
              artifact_type: :directory,
              path: "App.app/Design.bundle",
              size: 1,
              shasum: "bundle",
              collapsed?: false,
              children: [
                %{
                  id: "car",
                  artifact_id: "bundle",
                  artifact_type: :asset,
                  path: "App.app/Design.bundle/Assets.car",
                  size: 1,
                  shasum: "car",
                  collapsed?: false,
                  children: []
                }
              ]
            },
            %{
              id: "binary",
              artifact_id: "app",
              artifact_type: :binary,
              path: "App.app/App",
              size: 2,
              shasum: "binary",
              collapsed?: false,
              children: []
            }
          ]
        }
      ]

      [%{children: children}] = TuistWeb.BundleLive.build_tree_data(artifacts, MapSet.new())

      assert %{name: "Design.bundle/Assets.car", path: "App.app/Design.bundle/Assets.car"} =
               Enum.find(children, &(&1.id == "car"))
    end
  end

  describe "sunburst chart events" do
    test "highlighting the chart center while the root is selected shows the bundle", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project)
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # When
      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-highlighted-parent", %{})

      # Then
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table th", bundle.name)
    end

    test "selecting the chart center while the root is selected keeps the root", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project)
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # When
      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-selected-parent", %{})

      # Then
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "App.app")
    end

    test "selecting the chart center goes up past the directories the chart merged into one node", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_merged_directories(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?current-path=App.app/Frameworks/A.framework/Resources/Assets.car"
        )

      # When
      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-selected-parent", %{})

      # Then
      assert current_path_param(assert_patch(lv)) == "App.app/Frameworks"
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "A.framework")
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "B.framework")
    end

    test "selecting the chart center from a top-level directory goes back to the root", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_merged_directories(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?current-path=App.app")

      # When
      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-selected-parent", %{})

      # Then
      assert current_path_param(assert_patch(lv)) == nil
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "App.app")
    end

    test "highlighting the chart center shows the parent past the directories the chart merged into one node", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_merged_directories(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?current-path=App.app/Frameworks/A.framework/Resources/Assets.car"
        )

      # When
      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-highlighted-parent", %{})

      # Then
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table th", "Frameworks")
    end

    test "keeps the table's page after the pointer leaves a highlighted chart segment", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project, 12)
      path_hash = :md5 |> :crypto.hash("App.app") |> Base.encode16() |> String.slice(0, 8)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?#{[{"current-path", "App.app"}, {"bundle-size-analysis-table-page-#{path_hash}", "2"}]}"
        )

      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "file_7.png")

      # When
      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-highlighted-artifact", %{
        "artifact" => %{"name" => "file_1.png", "value" => 1024, "artifact_id" => nil, "children" => []}
      })

      render_hook(lv, "update-bundle-size-analysis-sunburst-chart-table-no-highlighted-artifact", %{})

      # Then
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "file_7.png")
      refute has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "file_12.png")
    end

    test "opens the top-level directory from the current-path param", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      bundle = bundle_with_merged_directories(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?current-path=App.app")

      # Then
      assert has_element?(lv, "#bundle-size-analysis-sunburst-chart-table td", "Frameworks")
      assert has_element?(lv, "#bundle-size-analysis-current-contents[data-current-path='App.app']")
    end
  end

  describe "pagination" do
    test "includes the last partial page of the file breakdown", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project, 21)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=file-breakdown")

      # Then
      assert has_element?(lv, "a[data-part='page-button'][href*='file-breakdown-page=2']")
    end

    test "includes the last partial page of the module breakdown", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_frameworks(project, 21)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=module-breakdown")

      # Then
      assert has_element?(lv, "a[data-part='page-button'][href*='module-breakdown-page=2']")
    end

    test "includes the last partial page of the bundle size analysis table", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project, 6)
      path_hash = :md5 |> :crypto.hash("App.app") |> Base.encode16() |> String.slice(0, 8)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?current-path=App.app")

      # Then
      assert has_element?(
               lv,
               "a[data-part='page-button'][href*='bundle-size-analysis-table-page-#{path_hash}=2']"
             )
    end

    test "keeps the file breakdown sort order when paging", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project, 21)

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=file-breakdown&file-breakdown-sort-by=size&file-breakdown-sort-order=asc"
        )

      # Then
      assert has_element?(
               lv,
               "a[data-part='page-button'][href*='file-breakdown-page=2'][href*='file-breakdown-sort-order=asc']"
             )
    end

    test "keeps the module breakdown search and sort when paging", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_frameworks(project, 21)

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=module-breakdown&module-breakdown-filter=Module&module-breakdown-sort-by=name&module-breakdown-sort-order=asc"
        )

      # Then
      assert has_element?(
               lv,
               "a[data-part='page-button'][href*='module-breakdown-page=2'][href*='module-breakdown-filter=Module'][href*='module-breakdown-sort-order=asc']"
             )
    end

    test "keeps the module breakdown sort when searching", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_frameworks(project, 21)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=module-breakdown&module-breakdown-sort-by=name&module-breakdown-sort-order=asc&module-breakdown-page=2"
        )

      # When
      render_hook(lv, "search-module-breakdown", %{"search" => "Module1"})

      # Then
      query = lv |> assert_patch() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert %{
               "module-breakdown-filter" => "Module1",
               "module-breakdown-sort-by" => "name",
               "module-breakdown-sort-order" => "asc"
             } = query

      refute Map.has_key?(query, "module-breakdown-page")
    end
  end

  describe "patching params" do
    test "re-sorts the file breakdown when only its sort order changes", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      bundle = bundle_with_files(project)
      path = ~p"/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}?tab=file-breakdown"
      {:ok, lv, _html} = live(conn, path)
      assert file_breakdown_paths(lv) == ["large.png", "small.png"]

      # When
      render_patch(lv, path <> "&file-breakdown-sort-by=size&file-breakdown-sort-order=asc")

      # Then
      assert file_breakdown_paths(lv) == ["small.png", "large.png"]
    end
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

  defp bundle_with_files(project, count) do
    files =
      for index <- 1..count do
        %{
          artifact_type: :asset,
          path: "App.app/file_#{index}.png",
          size: 1024 * index,
          shasum: "file-#{index}",
          children: []
        }
      end

    install_size = Enum.reduce(files, 0, &(&1.size + &2))

    BundlesFixtures.bundle_fixture(
      project: project,
      install_size: install_size,
      artifacts: [%{artifact_type: :directory, path: "App.app", size: install_size, shasum: "app", children: files}]
    )
  end

  defp bundle_with_frameworks(project, count) do
    frameworks =
      for index <- 1..count do
        %{
          artifact_type: :directory,
          path: "App.app/Module#{index}.framework",
          size: 1024 * index,
          shasum: "module-#{index}",
          children: []
        }
      end

    install_size = Enum.reduce(frameworks, 0, &(&1.size + &2))

    BundlesFixtures.bundle_fixture(
      project: project,
      install_size: install_size,
      artifacts: [%{artifact_type: :directory, path: "App.app", size: install_size, shasum: "app", children: frameworks}]
    )
  end

  # A.framework and A.framework/Resources have a single child each, so the chart draws
  # them as one node together with Assets.car.
  defp bundle_with_merged_directories(project) do
    assets = %{
      artifact_type: :asset,
      path: "App.app/Frameworks/A.framework/Resources/Assets.car",
      size: 4096,
      shasum: "assets",
      children: []
    }

    resources = %{
      artifact_type: :directory,
      path: "App.app/Frameworks/A.framework/Resources",
      size: 4096,
      shasum: "resources",
      children: [assets]
    }

    frameworks = %{
      artifact_type: :directory,
      path: "App.app/Frameworks",
      size: 6144,
      shasum: "frameworks",
      children: [
        %{
          artifact_type: :directory,
          path: "App.app/Frameworks/A.framework",
          size: 4096,
          shasum: "a",
          children: [resources]
        },
        %{artifact_type: :directory, path: "App.app/Frameworks/B.framework", size: 2048, shasum: "b", children: []}
      ]
    }

    info_plist = %{artifact_type: :file, path: "App.app/Info.plist", size: 1024, shasum: "info", children: []}

    BundlesFixtures.bundle_fixture(
      project: project,
      install_size: 7168,
      artifacts: [
        %{artifact_type: :directory, path: "App.app", size: 7168, shasum: "app", children: [frameworks, info_plist]}
      ]
    )
  end

  defp current_path_param(patched_path) do
    patched_path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.get("current-path")
  end

  defp bundle_with_files(project) do
    files = [
      %{artifact_type: :asset, path: "App.app/small.png", size: 1024, shasum: "small", children: []},
      %{artifact_type: :asset, path: "App.app/large.png", size: 4096, shasum: "large", children: []}
    ]

    BundlesFixtures.bundle_fixture(
      project: project,
      install_size: 5120,
      artifacts: [%{artifact_type: :directory, path: "App.app", size: 5120, shasum: "app", children: files}]
    )
  end

  defp file_breakdown_paths(lv) do
    lv
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#file-breakdown-table tbody tr")
    |> Enum.map(fn row -> row |> Floki.find("td") |> hd() |> Floki.text() |> String.trim() end)
  end

  defp duplicate_group_count(lv) do
    lv
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[id$='-insights-duplicate-collapsible']")
    |> length()
  end
end
