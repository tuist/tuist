defmodule Tuist.Tests.SelectionsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Selections
  alias Tuist.Tests.TestSelectionRun
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  # A selection run that skipped `test_refresh()` and `test_reset()`, whose
  # test run ran `test_load()` (passed) but never reported `test_gone()`.
  defp run(project) do
    test_run_id = UUIDv7.generate()
    [load, refresh, reset, gone] = for _ <- 1..4, do: UUIDv7.generate()

    run =
      TestSelectionFixtures.run_fixture(
        project_id: project.id,
        test_run_id: test_run_id,
        shard_count: 2,
        tests: [
          %{
            test_case_id: load,
            decision: "selected",
            module_name: "SearchTests",
            name: "test_load()",
            matched_path: "Sources/Search/Search.swift",
            estimated_duration_ms: 300
          },
          %{
            test_case_id: gone,
            decision: "selected",
            module_name: "SearchTests",
            name: "test_gone()",
            reason: "no_evidence",
            shard_index: 1,
            estimated_duration_ms: 100
          },
          %{
            test_case_id: refresh,
            decision: "skipped",
            module_name: "AuthTests",
            name: "test_refresh()",
            estimated_duration_ms: 500
          },
          %{
            test_case_id: reset,
            decision: "skipped",
            module_name: "AuthTests",
            name: "test_reset()",
            estimated_duration_ms: 200
          }
        ]
      )

    RunsFixtures.test_case_run_fixture(project_id: project.id, test_run_id: test_run_id, test_case_id: load, status: 0)

    run
  end

  describe "list_runs/2" do
    test "lists the project's selection runs newest first, filtered", %{project: project} do
      TestSelectionFixtures.run_fixture(
        project_id: project.id,
        git_commit_sha: "older",
        scheme: "Core",
        fallback_reason: "no_baseline",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      )

      TestSelectionFixtures.run_fixture(project_id: project.id, git_commit_sha: "newer")

      {rows, meta} = Selections.list_runs(project.id)

      assert Enum.map(rows, & &1.git_commit_sha) == ["newer", "older"]
      assert meta.total_count == 2
      assert {[%{git_commit_sha: "older"}], _meta} = Selections.list_runs(project.id, search: "core")
      assert {[%{git_commit_sha: "older"}], _meta} = Selections.list_runs(project.id, fallback: true)
    end
  end

  describe "get_run/2 and run_for_test_run/2" do
    test "find a selection run by its id and by the test run that reported it", %{project: project} do
      test_run_id = UUIDv7.generate()
      run = TestSelectionFixtures.run_fixture(project_id: project.id, test_run_id: test_run_id)

      assert {:ok, %{id: id}} = Selections.get_run(project.id, run.id)
      assert id == run.id
      assert {:error, :not_found} = Selections.get_run(project.id, UUIDv7.generate())
      assert {:error, :not_found} = Selections.get_run(project.id, "not-a-uuid")
      assert %{id: ^id} = Selections.run_for_test_run(project.id, test_run_id)
      assert is_nil(Selections.run_for_test_run(project.id, UUIDv7.generate()))
    end
  end

  describe "run_summary/1" do
    test "adds up the run's tests and the selected tests that never reported", %{project: project} do
      summary = project |> run() |> Selections.run_summary()

      assert summary.requested == 4
      assert summary.selected == 2
      assert summary.skipped == 2
      assert summary.skip_rate == 50.0
      assert summary.not_run == 1
      assert summary.reported

      assert summary.reasons == [
               %{decision: "selected", reason: "impacted", count: 1},
               %{decision: "selected", reason: "no_evidence", count: 1},
               %{decision: "skipped", reason: "unaffected", count: 2}
             ]
    end

    test "reports no outcomes before a test run reported", %{project: project} do
      run =
        TestSelectionFixtures.run_fixture(project_id: project.id, tests: [%{decision: "selected", name: "test_a()"}])

      assert %{reported: false, not_run: 0} = Selections.run_summary(run)
    end
  end

  describe "run_tests/2" do
    test "lists selected tests first with their outcomes", %{project: project} do
      {rows, meta} = project |> run() |> Selections.run_tests()

      assert Enum.map(rows, &{&1.name, &1.outcome}) == [
               {"test_gone()", nil},
               {"test_load()", "success"},
               {"test_refresh()", nil},
               {"test_reset()", nil}
             ]

      assert meta.total_count == 4
    end

    test "filters by decision, flag, shard and search, and sorts by duration", %{project: project} do
      run = run(project)

      assert {[%{name: "test_gone()"}], _meta} = Selections.run_tests(run, flag: "not_run")
      assert {[%{name: "test_gone()"}], _meta} = Selections.run_tests(run, shard: 1)
      assert {rows, _meta} = Selections.run_tests(run, decision: "skipped")
      assert Enum.map(rows, & &1.name) == ["test_refresh()", "test_reset()"]
      assert {[%{name: "test_load()"}], _meta} = Selections.run_tests(run, search: "load")

      assert {rows, _meta} = Selections.run_tests(run, sort_by: "duration", sort_order: "desc")
      assert Enum.map(rows, & &1.estimated_duration_ms) == [500, 300, 200, 100]
    end

    test "pages", %{project: project} do
      {rows, meta} = project |> run() |> Selections.run_tests(page: 2, page_size: 3)

      assert length(rows) == 1
      assert meta.total_pages == 2
      assert meta.current_page == 2
    end
  end

  describe "get_run_test/2" do
    test "returns one of the run's tests with its outcome", %{project: project} do
      run = run(project)
      {[test | _rest], _meta} = Selections.run_tests(run, search: "load")

      assert {:ok, %{name: "test_load()", outcome: "success"}} = Selections.get_run_test(run, test.test_case_id)
      assert {:error, :not_found} = Selections.get_run_test(run, UUIDv7.generate())
    end
  end

  describe "run_shards/1 and run_targets/1" do
    test "add up the run's tests per shard and per target", %{project: project} do
      run = run(project)

      assert Selections.run_shards(run) == [
               %{shard_index: 0, planned: 1, estimated_duration: 300, ran: 1, failed: 0, not_run: 0},
               %{shard_index: 1, planned: 1, estimated_duration: 100, ran: 0, failed: 0, not_run: 1}
             ]

      assert [
               %{module_name: "SearchTests", requested: 2, selected: 2, skipped: 0},
               %{module_name: "AuthTests", requested: 2, selected: 0, skipped: 2, estimated_skipped_duration: 700}
             ] = Selections.run_targets(run)
    end
  end

  describe "impacts" do
    test "find a run's impact and list its changed files", %{project: project} do
      TestSelectionFixtures.impact_fixture(
        project_id: project.id,
        baseline_sha: "older",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      )

      impact =
        TestSelectionFixtures.impact_fixture(
          project_id: project.id,
          baseline_sha: "newer",
          changed_files: [
            %{path: "docs/README.md", kind: "ignored"},
            %{path: "Sources/Search/Search.swift", impacted_tests_count: 2},
            %{path: "Sources/Auth/Session.swift", impacted_tests_count: 1}
          ]
        )

      run_with = fn baseline ->
        %TestSelectionRun{project_id: project.id, git_commit_sha: "a1b2c3d4e5f6", baseline_sha: baseline}
      end

      assert %{baseline_sha: "newer", changed_files_count: 3} = Selections.get_impact(run_with.("newer"))
      assert %{baseline_sha: "older"} = Selections.get_impact(run_with.("older"))
      assert Selections.get_impact(run_with.("")) == nil

      {rows, meta} = Selections.impact_changed_files(impact)

      assert Enum.map(rows, & &1.path) == [
               "Sources/Search/Search.swift",
               "Sources/Auth/Session.swift",
               "docs/README.md"
             ]

      assert meta.total_count == 3
      assert {[%{path: "docs/README.md"}], _meta} = Selections.impact_changed_files(impact, kind: "ignored")
    end
  end

  describe "analytics/2" do
    test "adds up the period's selection runs", %{project: project} do
      run(project)

      now = DateTime.utc_now()
      analytics = Selections.analytics(project.id, {DateTime.add(now, -7, :day), DateTime.add(now, 60, :second)})

      assert analytics.totals.runs == 1
      assert analytics.totals.selected == 2
      assert analytics.totals.skipped == 2
      assert analytics.totals.skip_rate == 50.0
      assert Enum.sum(analytics.selected) == 2
      assert length(analytics.dates) == 8
    end
  end
end
