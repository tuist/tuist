defmodule Tuist.Tests.SelectiveTestingCountsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.SelectiveTestingCount
  alias Tuist.Tests.SelectiveTestingCounts
  alias Tuist.Tests.Workers.SelectiveTestingCountsWorker
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  describe "record/1" do
    test "counts the tests of hit targets from the nearest earlier run that executed them", %{project: project} do
      # Given
      run(project, ~N[2026-11-01 10:00:00], [module("A", 9), module("B", 9)])
      run(project, ~N[2026-11-02 10:00:00], [module("A", 3), module("B", 2)])
      current = run(project, ~N[2026-11-03 10:00:00], [module("C", 4)])
      selective_testing(project, current, [{"A", :remote}, {"B", :local}, {"C", :miss}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{
               requested_test_count: 9,
               skipped_test_count: 5,
               skipped_module_count: 2,
               skipped_modules_without_history: 0
             } = row

      assert [%{requested_test_count: 9, skipped_test_count: 5}] = stored(current.id)
    end

    test "counts a hit target no earlier run executed as none and records it", %{project: project} do
      # Given
      run(project, ~N[2026-11-02 10:00:00], [module("A", 3)])
      current = run(project, ~N[2026-11-03 10:00:00], [module("C", 4)])
      selective_testing(project, current, [{"A", :local}, {"D", :remote}, {"C", :miss}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{
               requested_test_count: 7,
               skipped_test_count: 3,
               skipped_module_count: 2,
               skipped_modules_without_history: 1
             } = row
    end

    test "requests only what the run executed when nothing was hit", %{project: project} do
      # Given
      run(project, ~N[2026-11-02 10:00:00], [module("A", 3)])
      current = run(project, ~N[2026-11-03 10:00:00], [module("A", 3), module("C", 4)])
      selective_testing(project, current, [{"A", :miss}, {"C", :miss}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{requested_test_count: 7, skipped_test_count: 0, skipped_module_count: 0} = row
    end

    test "skips everything requested when every target was hit", %{project: project} do
      # Given
      run(project, ~N[2026-11-02 10:00:00], [module("A", 3), module("B", 2)])
      current = run(project, ~N[2026-11-03 10:00:00], [])
      selective_testing(project, current, [{"A", :remote}, {"B", :remote}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{requested_test_count: 5, skipped_test_count: 5, skipped_modules_without_history: 0} = row
    end

    test "prefers a run that wasn't narrowed to some of the target's tests, then one of the same scheme", %{
      project: project
    } do
      # Given
      run(project, ~N[2026-11-01 10:00:00], [module("A", 6)], scheme: "Other")
      run(project, ~N[2026-11-01 11:00:00], [module("A", 5)], scheme: "App")
      run(project, ~N[2026-11-01 12:00:00], [module("A", 4)], scheme: "Other")
      run(project, ~N[2026-11-02 10:00:00], [module("A", 1)], scheme: "App", only_test_identifiers: ["A/Suite/test"])
      current = run(project, ~N[2026-11-03 10:00:00], [], scheme: "App")
      selective_testing(project, current, [{"A", :remote}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{skipped_test_count: 5} = row
    end

    test "ignores runs that came later or are past the history window", %{project: project} do
      # Given
      run(project, ~N[2026-09-01 10:00:00], [module("A", 3)])
      current = run(project, ~N[2026-11-03 10:00:00], [])
      run(project, ~N[2026-11-04 10:00:00], [module("A", 3)])
      selective_testing(project, current, [{"A", :remote}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{skipped_test_count: 0, skipped_modules_without_history: 1} = row
    end

    test "counts nothing for a run without selective testing", %{project: project} do
      # Given
      current = run(project, ~N[2026-11-03 10:00:00], [module("A", 3)])
      CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: current.id)

      # When / Then
      assert SelectiveTestingCounts.record(current.id) == :skipped
      assert stored(current.id) == []
    end

    test "waits for a result bundle that is still processing", %{project: project} do
      # Given
      current = run(project, ~N[2026-11-03 10:00:00], [], status: "processing")
      selective_testing(project, current, [{"A", :remote}])

      # When / Then
      assert SelectiveTestingCounts.record(current.id) == :skipped
      assert stored(current.id) == []
    end

    test "takes a coverage-selected run's counts from its impact run", %{project: project} do
      # Given
      run(project, ~N[2026-11-02 10:00:00], [module("A", 3)])
      impact = impact_run(project, "selected", %{"A" => 5, "B" => 0}, requested: 40, selected: 15, skipped: 25)
      current = run(project, ~N[2026-11-03 10:00:00], [module("C", 15)], test_impact_run_id: impact.id)
      selective_testing(project, current, [{"A", :remote}, {"B", :local}, {"C", :miss}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{
               requested_test_count: 40,
               skipped_test_count: 25,
               skipped_module_count: 2,
               skipped_modules_without_history: 1
             } = row
    end

    test "counts a run whose selection fell back like any selective run", %{project: project} do
      # Given
      run(project, ~N[2026-11-02 10:00:00], [module("A", 3)])
      impact = impact_run(project, "fallback", %{"A" => 5}, requested: 9, selected: 4, skipped: 5)
      current = run(project, ~N[2026-11-03 10:00:00], [module("C", 4)], test_impact_run_id: impact.id)
      selective_testing(project, current, [{"A", :remote}, {"C", :miss}])

      # When
      {:ok, row} = SelectiveTestingCounts.record(current.id)

      # Then
      assert %{requested_test_count: 7, skipped_test_count: 3, skipped_modules_without_history: 0} = row
    end
  end

  describe "count_after_command_event/2" do
    test "schedules a count when the graph hashed a target for selective testing" do
      test_run_id = UUIDv7.generate()

      graph = %{
        "projects" => [
          %{"targets" => [%{"name" => "A", "selective_testing_metadata" => %{"hash" => "a", "hit" => "remote"}}]}
        ]
      }

      assert {:ok, _job} = SelectiveTestingCounts.count_after_command_event(%{test_run_id: test_run_id}, graph)
      assert_enqueued(worker: SelectiveTestingCountsWorker, args: %{test_run_id: test_run_id})
    end

    test "schedules nothing when no target was hashed" do
      graph = %{projects: [%{targets: [%{name: "A", binary_cache_metadata: %{hash: "a"}}]}]}

      assert SelectiveTestingCounts.count_after_command_event(%{test_run_id: UUIDv7.generate()}, graph) == :skipped
      refute_enqueued(worker: SelectiveTestingCountsWorker)
    end
  end

  defp run(project, ran_at, modules, opts \\ []) do
    {:ok, test} =
      RunsFixtures.test_fixture(
        Keyword.merge([project_id: project.id, ran_at: ran_at, test_modules: modules, scheme: "App"], opts)
      )

    test
  end

  defp impact_run(project, outcome, skipped_modules, counts) do
    {:ok, run} =
      Storage.create_run(%{
        project_id: project.id,
        head_sha: "head",
        commit_sha: "head",
        build_system: "xcode",
        outcome: outcome,
        skipped_modules: skipped_modules,
        requested_count: counts[:requested],
        selected_count: counts[:selected],
        skipped_count: counts[:skipped]
      })

    run
  end

  defp module(name, test_count) do
    %{
      name: name,
      status: "success",
      duration: 100,
      test_cases: for(index <- 1..test_count//1, do: %{name: "test#{index}()", status: "success", duration: 10})
    }
  end

  defp selective_testing(project, run, targets) do
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run.id)

    for {target, hit} <- targets do
      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: target,
        selective_testing_hash: "#{target}-hash",
        selective_testing_hit: hit
      )
    end
  end

  defp stored(test_run_id) do
    ClickHouseRepo.all(from(c in SelectiveTestingCount, hints: ["FINAL"], where: c.test_run_id == ^test_run_id))
  end
end
