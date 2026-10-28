defmodule TuistWeb.TestSelectionsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Selections
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures
  alias TuistWeb.Errors.NotFoundError

  defp plan(project, attrs \\ []) do
    TestSelectionFixtures.selection_fixture(
      Keyword.merge(
        [
          project_id: project.id,
          git_commit_sha: "a1b2c3d4e5f6a7b8",
          git_branch: "feature/search",
          decisions: [
            %{
              decision: "selected",
              module_name: "SearchTests",
              suite_name: "SearchViewModelTests",
              name: "test_load()",
              covered_paths: ["Sources/Search/SearchViewModel.swift", "Sources/Networking/APIClient.swift"],
              changed_paths: ["Sources/Search/SearchViewModel.swift"]
            },
            %{
              decision: "skipped",
              module_name: "AuthTests",
              suite_name: "SessionTests",
              name: "test_refresh()",
              scheme: "Core",
              covered_paths: ["Sources/Auth/Session.swift"]
            }
          ],
          changed_files: [
            %{path: "Sources/Search/SearchViewModel.swift", selected_count: 1},
            %{path: "docs/testing.md", kind: "ignored"}
          ]
        ],
        attrs
      )
    )
  end

  describe "the Test Selection page" do
    test "shows the period's figures and lists the plans with their test runs", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      plan(project)
      RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: "a1b2c3d4e5f6a7b8")

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")
      render_async(lv)

      assert has_element?(lv, "#widget-selected", "1")
      assert has_element?(lv, "#widget-skipped", "1")
      assert has_element?(lv, "#widget-skip-rate", "50.0%")
      assert has_element?(lv, "#test-selections-table", "a1b2c3d")
      assert has_element?(lv, "#test-selections-table", "feature/search")
      assert has_element?(lv, "#test-selections-table", "Dry run")
    end

    test "searches the plans and shows the empty state", %{conn: conn, organization: organization, project: project} do
      plan(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection?search=main")

      refute has_element?(lv, "#test-selections-table")
      assert has_element?(lv, "[data-part='empty-commits']")
    end

    test "flags plans that ran everything", %{conn: conn, organization: organization, project: project} do
      plan(project, fallback_reason: "tracked_file_changed")

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")

      assert has_element?(lv, "#test-selections-table", "Ran everything")
    end

    test "is not found without the coverage flag", %{conn: conn, organization: organization, project: project} do
      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")
      end
    end
  end

  describe "a commit's page" do
    test "summarizes the plan and lists its decisions, selected first", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      plan(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/a1b2c3d4e5f6a7b8")

      assert has_element?(lv, "h1", "a1b2c3d")
      assert has_element?(lv, "#widget-selected", "1")
      assert has_element?(lv, "#widget-targets", "1 / 2")
      assert has_element?(lv, "#test-selection-reasons-table", "Executes a changed file")

      rows =
        lv
        |> element("#test-selection-decisions-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()))

      assert [first, second] = rows
      assert first =~ "test_load()"
      assert first =~ "Selected"
      assert second =~ "test_refresh()"
      assert second =~ "Skipped"
      refute has_element?(lv, "[data-part='coverage-link']")
    end

    test "filters the decisions", %{conn: conn, organization: organization, project: project} do
      plan(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/a1b2c3d4e5f6a7b8?decision=skipped"
        )

      assert has_element?(lv, "#test-selection-decisions-table", "test_refresh()")
      refute has_element?(lv, "#test-selection-decisions-table", "test_load()")
    end

    test "lists the modified files and the commit's test runs", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      plan(project)
      RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: "a1b2c3d4e5f6a7b8", scheme: "App")

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/a1b2c3d4e5f6a7b8?tab=files"
        )

      assert has_element?(lv, "#test-selection-files-table", "SearchViewModel.swift")
      assert has_element?(lv, "#test-selection-files-table", "Ignored")

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/a1b2c3d4e5f6a7b8?tab=runs"
        )

      assert has_element?(lv, "#test-selection-runs-table", "App")
    end

    test "is not found for a commit without a plan", %{conn: conn, organization: organization, project: project} do
      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/missing")
      end
    end
  end

  describe "a decision's page" do
    test "explains the decision and lists the files the test executed, changed ones first", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      selection = plan(project)
      {[decision], _meta} = Selections.decisions(selection, search: "test_load")

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/a1b2c3d4e5f6a7b8/decisions/#{decision.id}"
        )

      assert has_element?(lv, "h1", "test_load()")
      assert has_element?(lv, "#test-selection-decision-reason", "Executes a changed file")
      assert has_element?(lv, "[data-part='file-details']", "Tests/AppTests/AppTests.swift")

      [first, second] =
        lv
        |> element("#test-selection-decision-files-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(&Floki.text/1)

      assert first =~ "SearchViewModel.swift"
      assert first =~ "Modified"
      assert second =~ "APIClient.swift"
      assert second =~ "Unchanged"
    end

    test "is not found for an unknown decision", %{conn: conn, organization: organization, project: project} do
      plan(project)

      assert_raise NotFoundError, fn ->
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/a1b2c3d4e5f6a7b8/decisions/#{Ecto.UUID.generate()}"
        )
      end
    end
  end
end
