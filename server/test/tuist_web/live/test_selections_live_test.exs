defmodule TuistWeb.TestSelectionsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistWeb.Errors.NotFoundError

  @sha "a1b2c3d4e5f6a7b8"

  defp selection(project, attrs \\ []) do
    load = UUIDv7.generate()
    refresh = UUIDv7.generate()

    TestSelectionFixtures.baseline_fixture(
      project_id: project.id,
      tests: [
        %{test_case_id: load, module_name: "SearchTests", suite_name: "SearchViewModelTests", name: "test_load()"},
        %{test_case_id: refresh, module_name: "AuthTests", suite_name: "SessionTests", name: "test_refresh()"}
      ]
    )

    run =
      TestSelectionFixtures.run_fixture(
        Keyword.merge(
          [
            project_id: project.id,
            commit_sha: @sha,
            skipped_count: 1,
            module_skipped_count: 2,
            rules_version: "2026-11-01",
            rule_trace: [
              %{rule: "tracked_files", selected: 0, skipped: 0, verdict: "continue"},
              %{rule: "impacted", selected: 1, skipped: 0, verdict: "continue"},
              %{rule: "unaffected", selected: 0, skipped: 1, verdict: "done"}
            ],
            selected: [
              %{
                test_case_id: load,
                module_name: "SearchTests",
                suite_name: "SearchViewModelTests",
                name: "test_load()",
                matched_path: "Sources/Search/SearchViewModel.swift"
              }
            ]
          ],
          attrs
        )
      )

    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: @sha, scheme: "App", test_impact_run_id: run.id)

    load_run =
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_run_id: test_run.id,
        test_case_id: load,
        module_name: "SearchTests",
        suite_name: "SearchViewModelTests",
        name: "test_load()",
        status: 0
      )

    TestSelectionFixtures.diff_fixture(
      project_id: project.id,
      commit_sha: @sha,
      changed_files: [
        %{path: "Sources/Search/SearchViewModel.swift"},
        %{path: "App/Project.swift"}
      ]
    )

    %{run: run, test_run: test_run, load_run: load_run}
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
      assert has_element?(lv, "#widget-skipped", "3")
      assert has_element?(lv, "#widget-skip-rate", "75.0%")
      assert has_element?(lv, "#test-selection-runs-table", "1 / 4")
      assert has_element?(lv, "#test-selection-runs-table", "a1b2c3d")
      assert has_element?(lv, "#test-selection-runs-table", "feature/search")
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
      selection(project, outcome: "fallback", reason: "history_unavailable")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection?fallback=true")

      assert has_element?(lv, "#test-selection-runs-table", "History too shallow")

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

    test "is not found without the test impact analysis flag", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      stub(Tuist.FeatureFlags, :test_impact_analysis_enabled?, fn _account, _project -> false end)

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-selection")
      end
    end
  end

  describe "a test run's selection tabs" do
    test "shows the selection's figures and tests", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{test_run: test_run, load_run: load_run} = selection(project)
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}"

      {:ok, lv, _html} = live(conn, path <> "?tab=test-optimizations")

      assert has_element?(lv, "#widget-selection-selected", "1 / 4")
      assert has_element?(lv, "#widget-selection-module-skipped", "2")
      assert has_element?(lv, "#widget-selection-skipped", "1")
      assert has_element?(lv, "#widget-selection-skip-rate", "75.0%")
      assert has_element?(lv, "#widget-selection-not-run", "0")
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
      assert first =~ "Selected"
      assert first =~ "Passed"
      assert second =~ "test_refresh()"
      assert second =~ "Skipped"
      assert second =~ "Not run"

      assert has_element?(
               lv,
               "#selection-tests-table a[href$='/tests/test-cases/runs/#{load_run.id}?tab=selective-testing']"
             )
    end

    test "shows the modules, changed files, shards and configuration", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{run: run, test_run: test_run} = selection(project)
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, granularity: "suite", test_impact_run_id: run.id)

      ShardsFixtures.shard_plan_test_suite_fixture(
        shard_plan_id: plan.id,
        project_id: project.id,
        module_name: "SearchTests",
        test_suite_name: "SearchViewModelTests"
      )

      path =
        ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=test-optimizations"

      {:ok, lv, _html} = live(conn, path)

      tabs =
        lv
        |> element("[data-part='coverage-selection']")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 =~ ~r/^(Tests|Modules|Changed files|Shards) \(|^Configuration$/))

      assert [tests, modules, files, shards, configuration] = tabs
      assert tests =~ "Tests"
      assert modules =~ "Modules"
      assert files =~ "Changed files"
      assert shards =~ "Shards"
      assert configuration == "Configuration"

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=files")
      assert has_element?(lv, "#selection-files-table", "SearchViewModel.swift")
      assert has_element?(lv, "#selection-files-table", "Tracked")

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=modules")
      assert has_element?(lv, "#selection-modules-table", "AuthTests")

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=shards")
      assert has_element?(lv, "#selection-shards-table", "Shard 0")

      {:ok, lv, _html} = live(conn, path <> "&selection-tab=configuration")
      assert has_element?(lv, "#selection-rules-version", "2026-11-01")
      assert has_element?(lv, "#selection-rule-trace-table", "unaffected")
      assert has_element?(lv, "#selection-rule-trace-table", "done")
      assert has_element?(lv, "#selection-tracked-files", "**/Package.resolved")
    end

    test "shows the module-level selection's hits next to the selection's modules", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{test_run: test_run} = selection(project)

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, test_run_id: test_run.id, name: "test")

      graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)
      xcode_project = XcodeFixtures.xcode_project_fixture(xcode_graph_id: graph.id)

      for {name, hit} <- [{"AuthTests", :miss}, {"CoreTests", :remote}] do
        XcodeFixtures.xcode_target_fixture(
          xcode_project_id: xcode_project.id,
          name: name,
          selective_testing_hash: "#{name}-hash",
          selective_testing_hit: hit
        )
      end

      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}"

      {:ok, lv, _html} = live(conn, path <> "?tab=test-optimizations&selection-tab=modules")

      assert has_element?(lv, "[data-part='coverage-selection'] #selective-testing-table")
      refute has_element?(lv, "#selection-modules-table")

      [auth, core] =
        lv
        |> element("#selective-testing-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/, " ")))
        |> Enum.filter(&(&1 =~ "-hash"))

      assert auth =~ "AuthTests"
      assert auth =~ "Missed"
      assert auth =~ "0 / 1"
      assert core =~ "CoreTests"
      assert core =~ "Remote"
      assert core =~ "–"
    end

    test "explains a fallback", %{conn: conn, organization: organization, project: project} do
      %{test_run: test_run} =
        selection(project,
          outcome: "fallback",
          reason: "tracked_file_changed",
          matched_path: "Package.resolved",
          rule_trace: [%{rule: "tracked_files", selected: 0, skipped: 0, verdict: "abort"}]
        )

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=test-optimizations"
        )

      assert has_element?(lv, "#test-selection-fallback", "Tracked file changed")
      assert has_element?(lv, "#test-selection-fallback", "Package.resolved")
      assert has_element?(lv, "#selection-rule-trace-table", "abort")
      refute has_element?(lv, "#selection-tests-table")
    end

    test "says when the run's impact run expired", %{conn: conn, organization: organization, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: UUIDv7.generate())
      path = ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}"

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "a[href*='tab=test-optimizations']", "Selective Testing")

      {:ok, lv, _html} = live(conn, path <> "?tab=test-optimizations")
      assert has_element?(lv, "#test-selection-expired")
    end

    test "links the overview's card to the Selective Testing tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      %{test_run: test_run} = selection(project)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert has_element?(lv, "a[href*='tab=test-optimizations']", "Selective Testing")
      assert has_element?(lv, "[data-part='test-selection-card']", "Selected by coverage")
      assert has_element?(lv, "[data-part='test-selection-card'] a[href*='tab=test-optimizations']")
    end
  end

  describe "a test case run's Selective Testing tab" do
    test "explains why a test was kept", %{conn: conn, organization: organization, project: project} do
      %{load_run: load_run} = selection(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases/runs/#{load_run.id}?tab=selective-testing"
        )

      assert has_element?(lv, "#test-selection-test-reason", "Selected: Executes a changed file")
      assert has_element?(lv, "#test-selection-test-reason", "SearchViewModel.swift")
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
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}?tab=selective-testing"
        )

      refute has_element?(lv, "[data-part='test-selection']")
      refute render(lv) =~ "tab=selective-testing"
    end
  end
end
