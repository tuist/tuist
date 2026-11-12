defmodule Tuist.Tests.RunSelectionsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.RunSelection
  alias Tuist.Tests.RunSelections
  alias Tuist.Tests.Workers.RecordRunSelectionWorker
  alias Tuist.Tests.Workers.RunSelectionsBackfillWorker
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture(), now: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)}
  end

  # A test run that executed `tests` tests in each module (`{module, tests}`),
  # plus `skipped` tests that reported `skipped` in the first module.
  defp test_run(project, ran_at, modules, attrs \\ []) do
    test_modules =
      modules
      |> Enum.with_index()
      |> Enum.map(fn {{module, tests}, index} ->
        skipped = if index == 0, do: Keyword.get(attrs, :skipped, 0), else: 0

        %{
          name: module,
          status: "success",
          duration: 100,
          test_cases:
            for(n <- 1..tests//1, do: %{name: "test_#{n}()", suite_name: "Suite", status: "success", duration: 10}) ++
              for(
                n <- 1..skipped//1,
                do: %{name: "test_skipped_#{n}()", suite_name: "Suite", status: "skipped", duration: 0}
              )
        }
      end)

    {:ok, run} =
      RunsFixtures.test_fixture(
        Keyword.merge(
          [project_id: project.id, ran_at: ran_at, test_modules: test_modules],
          Keyword.delete(attrs, :skipped)
        )
      )

    run
  end

  # The run's `tuist test` command event, with the selective-testing hash and
  # hit of each test target, `{name, hash, hit}`.
  defp command_event(project, run, targets) do
    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_run_id: run.id,
        ran_at: run.ran_at,
        created_at: run.ran_at,
        test_targets: Enum.map(targets, &elem(&1, 0)),
        local_test_target_hits: for({name, _hash, :local} <- targets, do: name),
        remote_test_target_hits: for({name, _hash, :remote} <- targets, do: name)
      )

    for {name, hash, hit} <- targets do
      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: name,
        selective_testing_hash: hash,
        selective_testing_hit: hit
      )
    end

    event
  end

  defp selection(project, run) do
    ClickHouseRepo.one(
      from(s in RunSelection,
        hints: ["FINAL"],
        where: s.project_id == ^project.id and s.test_run_id == ^run.id
      )
    )
  end

  defp days_ago(now, days), do: NaiveDateTime.add(now, -days * 86_400, :second)

  describe "record/2 for a run hashing alone selected" do
    test "counts a skipped module's tests in the run that stored its hash, and estimates the others from their latest run",
         %{project: project, now: now} do
      # AuthTests passed with hash h1 three days ago (3 tests, a fourth
      # skipped by XCTSkip), then grew to 5 tests under hash h2.
      stored = test_run(project, days_ago(now, 3), [{"AuthTests", 3}], skipped: 1)
      command_event(project, stored, [{"AuthTests", "h1", :miss}])
      grown = test_run(project, days_ago(now, 2), [{"AuthTests", 5}])
      command_event(project, grown, [{"AuthTests", "h2", :miss}])

      # ProfileTests last ran with 6 tests under another hash.
      profile = test_run(project, days_ago(now, 4), [{"ProfileTests", 6}])
      command_event(project, profile, [{"ProfileTests", "p0", :miss}])

      run = test_run(project, now, [{"CoreTests", 2}], is_ci: true, scheme: "App", git_branch: "feature")

      command_event(project, run, [
        {"AuthTests", "h1", :local},
        {"ProfileTests", "p1", :remote},
        {"CoreTests", "c1", :miss}
      ])

      assert RunSelections.record(project.id, [run.id]) == 1

      assert %{
               strategy: "module_hash",
               scope_tests: 11,
               avoided_tests: 9,
               estimated_tests: 6,
               avoided_by: %{"module_hash" => 9},
               is_ci: true,
               scheme: "App",
               git_branch: "feature",
               build_system: "xcode"
             } = selection(project, run)
    end

    test "estimates a module whose matching run narrowed it", %{project: project, now: now} do
      narrowed =
        test_run(project, days_ago(now, 3), [{"AuthTests", 2}], skip_test_identifiers: ["AuthTests/SessionTests"])

      command_event(project, narrowed, [{"AuthTests", "h1", :miss}])
      grown = test_run(project, days_ago(now, 2), [{"AuthTests", 5}])
      command_event(project, grown, [{"AuthTests", "h2", :miss}])

      run = test_run(project, now, [{"CoreTests", 1}])
      command_event(project, run, [{"AuthTests", "h1", :local}, {"CoreTests", "c1", :miss}])

      RunSelections.record(project.id, [run.id])

      assert %{avoided_tests: 5, estimated_tests: 5, scope_tests: 6} = selection(project, run)
    end

    test "leaves out the skipped modules a narrowed run didn't name whole", %{project: project, now: now} do
      earlier = test_run(project, days_ago(now, 2), [{"AuthTests", 5}, {"ProfileTests", 4}])
      command_event(project, earlier, [{"AuthTests", "h1", :miss}, {"ProfileTests", "p1", :miss}])

      run = test_run(project, now, [{"CoreTests", 1}], only_test_identifiers: ["CoreTests", "AuthTests"])

      command_event(project, run, [
        {"AuthTests", "h1", :local},
        {"ProfileTests", "p1", :local},
        {"CoreTests", "c1", :miss}
      ])

      RunSelections.record(project.id, [run.id])

      assert %{avoided_tests: 5, scope_tests: 6} = selection(project, run)
    end

    test "records no row for a run without selective testing", %{project: project, now: now} do
      run = test_run(project, now, [{"CoreTests", 3}])
      CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "test", test_run_id: run.id)

      assert RunSelections.record(project.id, [run.id]) == 0
      assert selection(project, run) == nil
    end
  end

  describe "record/2 for a run coverage-based selection decided" do
    test "takes the impact run's skipped tests, those in hash-skipped modules estimated", %{project: project, now: now} do
      impact_run =
        TestSelectionFixtures.run_fixture(
          project_id: project.id,
          skipped_modules: %{"BillingTests" => 4},
          skipped_count: 10,
          requested_count: 20
        )

      run = test_run(project, now, [{"SearchTests", 7}], skipped: 2, test_impact_run_id: impact_run.id)

      RunSelections.record(project.id, [run.id])

      assert %{
               strategy: "coverage",
               scope_tests: 17,
               avoided_tests: 10,
               estimated_tests: 4,
               avoided_by: %{"coverage" => 6, "module_hash" => 4}
             } = selection(project, run)
    end

    test "counts a run without a baseline like one hashing alone selected", %{project: project, now: now} do
      billing = test_run(project, days_ago(now, 1), [{"BillingTests", 3}])
      command_event(project, billing, [{"BillingTests", "b1", :miss}])

      impact_run =
        TestSelectionFixtures.run_fixture(
          project_id: project.id,
          outcome: "fallback",
          reason: "no_baseline",
          baseline_sha: nil,
          requested_modules: ["SearchTests"],
          skipped_modules: %{"BillingTests" => 0}
        )

      run = test_run(project, now, [{"SearchTests", 7}], test_impact_run_id: impact_run.id)

      RunSelections.record(project.id, [run.id])

      assert %{strategy: "coverage", scope_tests: 10, avoided_tests: 3, estimated_tests: 3} = selection(project, run)
    end
  end

  describe "enqueue/2" do
    test "queues a run with an impact run when it is reported", %{project: project, now: now} do
      impact_run = TestSelectionFixtures.run_fixture(project_id: project.id)
      run = test_run(project, now, [{"SearchTests", 1}], test_impact_run_id: impact_run.id)

      assert_enqueued(worker: RecordRunSelectionWorker, args: %{project_id: project.id, test_run_id: run.id})
    end
  end

  describe "backfill/2" do
    test "records the project's earlier runs from their command events and impact runs", %{project: project, now: now} do
      hashed = test_run(project, days_ago(now, 1), [{"CoreTests", 2}])
      command_event(project, hashed, [{"CoreTests", "c1", :miss}])

      impact_run = TestSelectionFixtures.run_fixture(project_id: project.id, skipped_count: 3)
      selected = test_run(project, now, [{"SearchTests", 1}], test_impact_run_id: impact_run.id)

      assert RunSelections.backfill(project.id) == :done
      assert %{scope_tests: 2, avoided_tests: 0} = selection(project, hashed)
      assert %{scope_tests: 4, avoided_tests: 3} = selection(project, selected)
    end
  end

  describe "RunSelectionsBackfillWorker" do
    test "fills every project's recent runs, then their older ones, one job at a time", %{project: project, now: now} do
      old = test_run(project, days_ago(now, 40), [{"CoreTests", 2}])
      command_event(project, old, [{"CoreTests", "c1", :miss}])

      other_project = ProjectsFixtures.project_fixture()
      recent = test_run(other_project, days_ago(now, 1), [{"CoreTests", 3}])
      command_event(other_project, recent, [{"CoreTests", "c1", :miss}])

      assert :ok = perform_job(RunSelectionsBackfillWorker, %{project_ids: [project.id, other_project.id]})
      assert [%{args: %{"pass" => "recent"}}] = all_enqueued(worker: RunSelectionsBackfillWorker)

      # Starting it again while the chain waits doesn't start a second chain.
      assert :ok = Tuist.Release.backfill_test_run_selections(project.id)
      assert [%{args: %{"pass" => "recent"}}] = all_enqueued(worker: RunSelectionsBackfillWorker)

      Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)

      assert %{scope_tests: 2} = selection(project, old)
      assert %{scope_tests: 3} = selection(other_project, recent)
      assert all_enqueued(worker: RunSelectionsBackfillWorker) == []
    end
  end
end
