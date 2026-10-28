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

  @sha "a1b2c3d4e5f6a7b8"

  defp selection(project, attrs \\ []) do
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: @sha, scheme: "App")
    load = UUIDv7.generate()
    refresh = UUIDv7.generate()

    run =
      TestSelectionFixtures.run_fixture(
        Keyword.merge(
          [
            project_id: project.id,
            git_commit_sha: @sha,
            test_run_id: test_run.id,
            missed_count: 1,
            tests: [
              %{
                test_case_id: load,
                decision: "selected",
                module_name: "SearchTests",
                suite_name: "SearchViewModelTests",
                name: "test_load()",
                matched_path: "Sources/Search/SearchViewModel.swift"
              },
              %{
                test_case_id: refresh,
                decision: "skipped",
                module_name: "AuthTests",
                suite_name: "SessionTests",
                name: "test_refresh()"
              }
            ]
          ],
          attrs
        )
      )

    RunsFixtures.test_case_run_fixture(project_id: project.id, test_run_id: test_run.id, test_case_id: load, status: 0)
    RunsFixtures.test_case_run_fixture(project_id: project.id, test_run_id: test_run.id, test_case_id: refresh, status: 1)

    TestSelectionFixtures.impact_fixture(
      project_id: project.id,
      head_sha: @sha,
      changed_files: [
        %{path: "Sources/Search/SearchViewModel.swift", impacted_tests_count: 1},
        %{path: "docs/testing.md", kind: "ignored"}
      ],
      tests: [
        %{
          test_case_id: load,
          module_name: "SearchTests",
          suite_name: "SearchViewModelTests",
          name: "test_load()",
          reason: "impacted",
          matched_path: "Sources/Search/SearchViewModel.swift"
        }
      ]
    )

    %{run: run, test_run: test_run}
  end

  describe "the Test Selection page" do
    test "shows the period's figures and lists the selection runs", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      selection(project)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")
      render_async(lv)

      assert has_element?(lv, "#widget-selected", "1")
      assert has_element?(lv, "#widget-skipped", "1")
      assert has_element?(lv, "#widget-skip-rate", "50.0%")
      assert has_element?(lv, "#widget-missed", "1")
      assert has_element?(lv, "#test-selection-runs-table", "a1b2c3d")
      assert has_element?(lv, "#test-selection-runs-table", "feature/search")
      assert has_element?(lv, "#test-selection-runs-table", "Dry run")
    end

    test "filters the runs that ran everything", %{conn: conn, organization: organization, project: project} do
      selection(project, fallback_reason: "timeout")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection?fallback=true")

      assert has_element?(lv, "#test-selection-runs-table", "Timed out")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection?search=main")

      refute has_element?(lv, "#test-selection-runs-table")
      assert has_element?(lv, "[data-part='empty-runs']")
    end

    test "shows the baselines tab", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection?tab=baselines")

      assert has_element?(lv, "[data-part='empty-baselines']")
    end

    test "is not found without the coverage flag", %{conn: conn, organization: organization, project: project} do
      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")
      end
    end
  end

  describe "a commit's page" do
    test "shows the impact, its runs, changed files and affected tests", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      selection(project)
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/#{@sha}"

      {:ok, lv, _html} = live(conn, path)

      assert has_element?(lv, "h1", "a1b2c3d")
      assert has_element?(lv, "[data-part='plan-card']", "0f0f0f0")
      assert has_element?(lv, "#test-selection-commit-runs-table", "App")
      refute has_element?(lv, "[data-part='coverage-link']")

      {:ok, lv, _html} = live(conn, path <> "?tab=files")
      assert has_element?(lv, "#test-selection-files-table", "SearchViewModel.swift")
      assert has_element?(lv, "#test-selection-files-table", "Ignored")

      {:ok, lv, _html} = live(conn, path <> "?tab=tests")
      assert has_element?(lv, "#test-selection-affected-table", "test_load()")
      assert has_element?(lv, "#test-selection-affected-table", "Executes a changed file")
    end

    test "is not found for a commit without a selection", %{conn: conn, organization: organization, project: project} do
      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/commits/missing")
      end
    end
  end

  describe "a selection run's page" do
    test "summarizes the run and lists its tests with their outcomes, misses flagged", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{run: run} = selection(project)
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/runs/#{run.id}"

      {:ok, lv, _html} = live(conn, path)

      assert has_element?(lv, "h1", "App")
      assert has_element?(lv, "#widget-selected", "1 / 2")
      assert has_element?(lv, "#widget-missed", "1")
      assert has_element?(lv, "#test-selection-reasons-table", "Executes a changed file")

      rows =
        lv
        |> element("#test-selection-run-tests-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()))

      assert [first, second] = rows
      assert first =~ "test_load()"
      assert first =~ "Passed"
      assert second =~ "test_refresh()"
      assert second =~ "Missed"

      {:ok, lv, _html} = live(conn, path <> "?tab=shards")
      assert has_element?(lv, "#test-selection-run-shards-table", "Shard 0")

      {:ok, lv, _html} = live(conn, path <> "?tab=targets")
      assert has_element?(lv, "#test-selection-run-targets-table", "AuthTests")
    end

    test "explains a fallback", %{conn: conn, organization: organization, project: project} do
      %{run: run} = selection(project, fallback_reason: "no_baseline", baseline_sha: "")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/runs/#{run.id}")

      assert has_element?(lv, "#test-selection-run-fallback", "No baseline")
    end

    test "is not found for an unknown run", %{conn: conn, organization: organization, project: project} do
      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/runs/#{UUIDv7.generate()}")
      end
    end
  end

  describe "a test's page" do
    test "explains the decision and its outcome", %{conn: conn, organization: organization, project: project} do
      %{run: run} = selection(project)
      {[test], _meta} = Selections.run_tests(run, search: "test_refresh")

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/runs/#{run.id}/tests/#{test.test_case_id}"
        )

      assert has_element?(lv, "h1", "test_refresh()")
      assert has_element?(lv, "#test-selection-test-reason", "No executed file changed")
      assert has_element?(lv, "#test-selection-test-miss")
    end

    test "is not found for a test outside the run", %{conn: conn, organization: organization, project: project} do
      %{run: run} = selection(project)

      assert_raise NotFoundError, fn ->
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-selection/runs/#{run.id}/tests/#{UUIDv7.generate()}"
        )
      end
    end
  end

  describe "a test run's page" do
    test "links to the selection run that chose its tests", %{conn: conn, organization: organization, project: project} do
      %{run: run, test_run: test_run} = selection(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert has_element?(lv, "[data-part='test-selection-card']", "Selected by coverage")

      assert has_element?(
               lv,
               "[data-part='test-selection-card'] a[href$='/tests/test-selection/runs/#{run.id}']"
             )
    end
  end
end
