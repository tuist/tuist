defmodule TuistWeb.TestSelectionsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

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

    load_run =
      RunsFixtures.test_case_run_fixture(project_id: project.id, test_run_id: test_run.id, test_case_id: load, status: 0)

    refresh_run =
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_run_id: test_run.id,
        test_case_id: refresh,
        status: 1
      )

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

    %{run: run, test_run: test_run, load_run: load_run, refresh_run: refresh_run}
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

    test "opens a run's test run on its Selective Testing tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{test_run: test_run} = selection(project)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")

      assert has_element?(
               lv,
               "#test-selection-runs-table a[href$='/tests/test-runs/#{test_run.id}?tab=test-optimizations']"
             )
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

  describe "a test run's Selective Testing tab" do
    test "shows the dry run's verdict, figures and tests, misses flagged", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{test_run: test_run, load_run: load_run} = selection(project)
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}"

      {:ok, lv, _html} = live(conn, path <> "?tab=test-optimizations")

      assert has_element?(lv, "#test-selection-dry-run", "Dry run: 1 miss")
      assert has_element?(lv, "#widget-selection-selected", "1 / 2")
      assert has_element?(lv, "#widget-selection-missed", "1")
      assert has_element?(lv, "[data-part='selection-summary-card']", "0f0f0f0")
      assert has_element?(lv, "[data-part='selection-summary-card']", "2 files")

      rows =
        lv
        |> element("#selection-tests-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()))

      assert [first, second] = rows
      assert first =~ "test_load()"
      assert first =~ "Would run"
      assert first =~ "Passed"
      assert second =~ "test_refresh()"
      assert second =~ "Would skip"
      assert second =~ "Missed"

      assert has_element?(
               lv,
               "#selection-tests-table a[href$='/tests/test-cases/runs/#{load_run.id}?tab=test-selection']"
             )

      {:ok, lv, _html} = live(conn, path <> "?tab=test-optimizations&selection-flag=missed")
      refute has_element?(lv, "#selection-tests-table", "test_load()")
      assert has_element?(lv, "#selection-tests-table", "test_refresh()")
    end

    test "shows the changed files, targets and shards", %{conn: conn, organization: organization, project: project} do
      %{test_run: test_run} = selection(project, shard_count: 2)
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=test-optimizations"

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=files")
      assert has_element?(lv, "#selection-files-table", "SearchViewModel.swift")
      assert has_element?(lv, "#selection-files-table", "Ignored")

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=targets")
      assert has_element?(lv, "#selection-targets-table", "AuthTests")

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=shards")
      assert has_element?(lv, "#selection-shards-table", "Shard 0")
    end

    test "explains a fallback", %{conn: conn, organization: organization, project: project} do
      %{test_run: test_run} = selection(project, fallback_reason: "no_baseline", baseline_sha: "")

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=test-optimizations"
        )

      assert has_element?(lv, "#test-selection-fallback", "No baseline")
      refute has_element?(lv, "#test-selection-dry-run")
    end

    test "names enforced skips without a verdict", %{conn: conn, organization: organization, project: project} do
      %{test_run: test_run} = selection(project, mode: "enabled", missed_count: 0)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=test-optimizations"
        )

      refute has_element?(lv, "#test-selection-dry-run")
      assert has_element?(lv, "#widget-selection-skipped", "1")
      assert has_element?(lv, "#widget-selection-not-run")
      assert has_element?(lv, "#selection-tests-table", "Skipped")
    end

    test "links the overview's card to the tab", %{conn: conn, organization: organization, project: project} do
      %{test_run: test_run} = selection(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert has_element?(lv, "[data-part='test-selection-card']", "Selected by coverage")
      assert has_element?(lv, "[data-part='test-selection-card'] a[href*='tab=test-optimizations']")
    end
  end

  describe "a test case run's Test Selection tab" do
    test "explains a miss", %{conn: conn, organization: organization, project: project} do
      %{refresh_run: refresh_run} = selection(project)
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-cases/runs/#{refresh_run.id}"

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "[data-part='header']", "Selection miss")

      {:ok, lv, _html} = live(conn, path <> "?tab=test-selection")
      assert has_element?(lv, "#test-selection-test-reason", "Would skip: No executed file changed")
      assert has_element?(lv, "#test-selection-test-miss")
    end

    test "explains why a test was kept", %{conn: conn, organization: organization, project: project} do
      %{load_run: load_run} = selection(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases/runs/#{load_run.id}?tab=test-selection"
        )

      assert has_element?(lv, "#test-selection-test-reason", "Executes a changed file")
      refute has_element?(lv, "#test-selection-test-miss")
      assert has_element?(lv, "#selection-executed-files-table", "SearchViewModel.swift")
    end

    test "is absent for a test run without a selection", %{conn: conn, organization: organization, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      test_case_run =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_run_id: test_run.id,
          test_case_id: UUIDv7.generate()
        )

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}?tab=test-selection"
        )

      refute has_element?(lv, "[data-part='test-selection']")
      refute render(lv) =~ "tab=test-selection"
    end
  end
end
