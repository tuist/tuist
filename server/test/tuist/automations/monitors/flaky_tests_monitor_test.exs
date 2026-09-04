defmodule Tuist.Automations.Monitors.FlakyTestsMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "evaluate/1" do
    test "fires for any test case with rate below the threshold (no implicit is_flaky scoping)" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "calm", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 5, "window_type" => "last_days", "window" => "1d", "comparison" => "lt"}
        )

      # The test case has 1 run, 0 flaky → rate = 0%, below 5%. The fact that
      # is_flaky is false on the row doesn't matter; the worker's baseline is
      # what silences this initial state.
      assert %{triggered: [triggered_id]} = FlakyTestsMonitor.evaluate(alert)
      assert triggered_id == test_case.id
    end

    test "skips test cases with no runs at all (no measurement to compare)" do
      project = ProjectsFixtures.project_fixture()

      # A TestCase row exists but no TestCaseRun: the MV has nothing to
      # aggregate for it, so the GROUP BY excludes it entirely.
      orphan_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: orphan_id, name: "no_runs")

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 5, "window_type" => "last_days", "window" => "30d", "comparison" => "lt"}
        )

      refute orphan_id in FlakyTestsMonitor.evaluate(alert).triggered
    end

    test "skips test cases whose rate meets the threshold" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "still_flaky", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      for ran_at <- [
            NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day),
            NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day)
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 50, "window_type" => "last_days", "window" => "30d", "comparison" => "lt"}
        )

      # 100% flaky rate, threshold 50% lt → does not fire.
      refute test_case.id in FlakyTestsMonitor.evaluate(alert).triggered
    end
  end

  describe "evaluate_by_run_count/1 lt comparison" do
    test "fires for tests with flaky run count below threshold (any test, including never-flagged)" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "calm", status: "success", duration: 100},
                %{name: "still_flaky", status: "success", duration: 100}
              ]
            }
          ]
        )

      {test_cases, _meta} = Tests.list_test_cases(project.id, %{})
      still_flaky = Enum.find(test_cases, &(&1.name == "still_flaky"))

      for _ <- 1..2 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: still_flaky.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 2, "window_type" => "last_days", "window" => "30d", "comparison" => "lt"}
        )

      triggered = FlakyTestsMonitor.evaluate_by_run_count(alert).triggered

      # `calm` has 0 flaky runs → < 2, fires. `still_flaky` has 2 → not < 2.
      calm = Enum.find(test_cases, &(&1.name == "calm"))
      assert calm.id in triggered
      refute still_flaky.id in triggered
    end
  end

  describe "evaluate_by_run_count/1 gt comparison" do
    test "fires when count is strictly greater than threshold" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      for _ <- 1..3 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 2, "window_type" => "last_days", "window" => "30d", "comparison" => "gt"}
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert test_case.id in triggered
    end
  end

  describe "evaluate_by_run_count/1 default comparison" do
    test "treats missing comparison as gte" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      for _ <- 1..3 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 3, "window_type" => "last_days", "window" => "30d"}
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert test_case.id in triggered
    end
  end

  describe "evaluate_by_reliability_rate/1" do
    test "fires for test cases whose success rate is below the threshold" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "unreliable")

      base = NaiveDateTime.utc_now()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: "success",
        ran_at: base,
        inserted_at: base
      )

      for i <- 1..9 do
        timestamp = NaiveDateTime.add(base, -i, :hour)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: "failure",
          ran_at: timestamp,
          inserted_at: timestamp
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 20, "window_type" => "last_days", "window" => "30d", "comparison" => "lt"}
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_reliability_rate(alert)
      assert test_case_id in triggered
    end

    test "skips test cases whose success rate is above the threshold" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "reliable")

      for i <- 1..5 do
        timestamp = NaiveDateTime.add(NaiveDateTime.utc_now(), -i, :hour)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: "success",
          ran_at: timestamp,
          inserted_at: timestamp
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d", "comparison" => "lt"}
        )

      refute test_case_id in FlakyTestsMonitor.evaluate_by_reliability_rate(alert).triggered
    end

    test "treats missing comparison as lt" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "legacy_reliability")

      # Enough runs to clear the scoped sample floor, all failing, so the rate is
      # 0% and only the comparison direction decides whether this fires.
      for _ <- 1..10 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: "failure"
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 50, "window_type" => "last_days", "window" => "30d"}
        )

      assert test_case_id in FlakyTestsMonitor.evaluate_by_reliability_rate(alert).triggered
    end
  end

  describe "evaluate/1 with rolling window" do
    test "computes flakiness rate over the last N runs per test case" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      # Older runs: 5 stable. Most recent: 5 flaky. Rolling window of 5 sees
      # only the flaky tail (100% rate); a calendar 30d window would see all
      # 10 runs (50% rate). The two modes should disagree here.
      base = NaiveDateTime.utc_now()

      for i <- 1..5 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: false,
          ran_at: NaiveDateTime.add(base, -10 + i, :day),
          inserted_at: NaiveDateTime.add(base, -10 + i, :day)
        )
      end

      for i <- 1..5 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -i, :hour),
          inserted_at: NaiveDateTime.add(base, -i, :hour)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 80,
            "window_type" => "rolling",
            "rolling_window_size" => 5,
            "comparison" => "gte"
          }
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate(alert)
      assert test_case.id in triggered
    end

    test "skips test cases whose last N runs are below the threshold" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      base = NaiveDateTime.utc_now()

      for i <- 1..5 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: false,
          ran_at: NaiveDateTime.add(base, -i, :hour),
          inserted_at: NaiveDateTime.add(base, -i, :hour)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 5,
            "comparison" => "gte"
          }
        )

      refute test_case.id in FlakyTestsMonitor.evaluate(alert).triggered
    end

    test "uses the fast-path latest 75 runs and ignores older flaky history" do
      project = ProjectsFixtures.project_fixture()
      base = NaiveDateTime.utc_now()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      for i <- 1..5 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -90 + i, :day),
          inserted_at: NaiveDateTime.add(base, -90 + i, :day)
        )
      end

      for i <- 1..75 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: false,
          ran_at: NaiveDateTime.add(base, i, :second),
          inserted_at: NaiveDateTime.add(base, i, :second)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 75,
            "comparison" => "gte"
          }
        )

      refute test_case.id in FlakyTestsMonitor.evaluate(alert).triggered
    end
  end

  describe "evaluate_rolling_alerts/2" do
    test "executes rolling queries through the read repository" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()
      ran_at = NaiveDateTime.utc_now()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: true,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 1,
            "comparison" => "gte",
            "window_type" => "rolling",
            "rolling_window_size" => 1
          }
        )

      with_read_repo(fn ->
        assert FlakyTestsMonitor.evaluate(alert, [test_case_id]).triggered == [test_case_id]

        triggered_by_alert_id =
          FlakyTestsMonitor.evaluate_rolling_alerts([alert], [test_case_id])

        assert triggered_by_alert_id[alert.id] == [test_case_id]
      end)
    end

    test "shares measurements between flakiness rate and flaky run count alerts" do
      project = ProjectsFixtures.project_fixture()
      one_flaky_run_id = Ecto.UUID.generate()
      two_flaky_runs_id = Ecto.UUID.generate()
      base = NaiveDateTime.utc_now()

      for {test_case_id, flaky_run_count} <- [{one_flaky_run_id, 1}, {two_flaky_runs_id, 2}],
          run_number <- 1..5 do
        ran_at = NaiveDateTime.add(base, -run_number, :minute)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: run_number <= flaky_run_count,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      rate_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 20,
            "comparison" => "gte",
            "window_type" => "rolling",
            "rolling_window_size" => 5
          }
        )

      count_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 2,
            "comparison" => "gte",
            "window_type" => "rolling",
            "rolling_window_size" => 5
          }
        )

      triggered_by_alert_id =
        FlakyTestsMonitor.evaluate_rolling_alerts(
          [rate_alert, count_alert],
          [one_flaky_run_id, two_flaky_runs_id]
        )

      assert MapSet.new(triggered_by_alert_id[rate_alert.id]) ==
               MapSet.new([one_flaky_run_id, two_flaky_runs_id])

      assert triggered_by_alert_id[count_alert.id] == [two_flaky_runs_id]
    end
  end

  describe "evaluate_by_run_count/1 with rolling window" do
    test "fires when flaky run count in last N runs meets the threshold" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      base = NaiveDateTime.utc_now()

      for i <- 1..3 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -i, :hour),
          inserted_at: NaiveDateTime.add(base, -i, :hour)
        )
      end

      # The run from the fixture above plus these fills the five-run window, so
      # the threshold is compared against the window the alert asked for.
      for i <- 4..6 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: false,
          ran_at: NaiveDateTime.add(base, -i, :hour),
          inserted_at: NaiveDateTime.add(base, -i, :hour)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 2,
            "window_type" => "rolling",
            "rolling_window_size" => 5,
            "comparison" => "gte"
          }
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert test_case.id in triggered
    end

    test "scopes rolling evaluation to the affected test cases" do
      project = ProjectsFixtures.project_fixture()
      included_id = Ecto.UUID.generate()
      excluded_id = Ecto.UUID.generate()
      base = NaiveDateTime.utc_now()

      for test_case_id <- [included_id, excluded_id] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -1, :second),
          inserted_at: NaiveDateTime.add(base, -1, :second)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 1,
            "comparison" => "gte"
          }
        )

      triggered = FlakyTestsMonitor.evaluate_by_run_count(alert, [included_id]).triggered

      assert included_id in triggered
      refute excluded_id in triggered
    end

    test "clamps a persisted window above the product cap instead of failing" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "over_cap")

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 1000,
            "comparison" => "gte"
          }
        )

      legacy_alert = put_in(alert.trigger_config["rolling_window_size"], 1001)

      # The changeset rejects anything above the cap and the worker skips such
      # alerts, so this only guards data persisted before the cap existed: it
      # evaluates at the cap rather than raising against a bucket that cannot
      # serve it.
      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_run_count(legacy_alert)
    end

    test "ignores runs outside the rolling window" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "tc", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      base = NaiveDateTime.utc_now()

      # 3 flaky runs, all older than the most recent stable runs that fill the
      # rolling window. Rolling-of-2 sees only the stable tail and reports 0
      # flaky; a 30d calendar window would still count the older flaky runs.
      for i <- 1..3 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -10 + i, :day),
          inserted_at: NaiveDateTime.add(base, -10 + i, :day)
        )
      end

      for i <- 1..2 do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: false,
          ran_at: NaiveDateTime.add(base, -i, :hour),
          inserted_at: NaiveDateTime.add(base, -i, :hour)
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 2,
            "comparison" => "gte"
          }
        )

      refute test_case.id in FlakyTestsMonitor.evaluate_by_run_count(alert).triggered
    end
  end

  describe "evaluate_by_reliability_rate/1 with rolling window" do
    test "computes reliability over the last N runs per test case" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "rolling_unreliable")

      base = NaiveDateTime.utc_now()

      for i <- 1..5 do
        timestamp = NaiveDateTime.add(base, -10 + i, :day)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: "success",
          ran_at: timestamp,
          inserted_at: timestamp
        )
      end

      for i <- 1..5 do
        timestamp = NaiveDateTime.add(base, -i, :hour)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: "failure",
          ran_at: timestamp,
          inserted_at: timestamp
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{
            "threshold" => 50,
            "window_type" => "rolling",
            "rolling_window_size" => 5,
            "comparison" => "lt"
          }
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_reliability_rate(alert)
      assert test_case_id in triggered
    end
  end

  describe "rolling window de-duplicates re-inserted runs" do
    # `test_case_runs` is a ReplacingMergeTree and flaky detection re-inserts a
    # run when it sets `is_flaky` after ingestion. The recent-runs MVs record
    # every physical insert, so one logical run can appear several times in the
    # rolling aggregate. Because the duplicates land only on flaky/failed runs
    # (successes are never re-marked), they inflate flakiness and deflate
    # reliability for the exact runs the thresholds care about. The monitor must
    # count each run once.
    test "flakiness_rate does not double-count a re-inserted flaky run" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "occasionally_flaky")

      insert_run_with_reinserted_flaky_tail(project.id, test_case_id)

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 25,
            "window_type" => "rolling",
            "rolling_window_size" => 5,
            "comparison" => "gte"
          }
        )

      # Last 5 distinct runs hold 1 flaky run → 20%, below the 25% threshold.
      # Counting the re-inserted run three times reports 3/5 = 60% and wrongly
      # mutes a healthy test.
      refute test_case_id in FlakyTestsMonitor.evaluate(alert).triggered
    end

    test "flakiness_rate still counts a re-inserted flaky run once (keeps the flaky mark)" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "occasionally_flaky")

      insert_run_with_reinserted_flaky_tail(project.id, test_case_id)

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 15,
            "window_type" => "rolling",
            "rolling_window_size" => 5,
            "comparison" => "gte"
          }
        )

      # De-duplicating must not drop the flaky mark: the run is still flaky
      # (the re-marks set is_flaky=true), so 1/5 = 20% clears the 15% threshold.
      assert test_case_id in FlakyTestsMonitor.evaluate(alert).triggered
    end

    test "reliability_rate does not double-count a re-inserted failing run" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "mostly_reliable")

      base = NaiveDateTime.utc_now()

      for i <- 1..9 do
        ran_at = NaiveDateTime.add(base, -i, :minute)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: "success",
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      failing_run_id = UUIDv7.generate()

      for _ <- 1..3 do
        RunsFixtures.test_case_run_fixture(
          id: failing_run_id,
          project_id: project.id,
          test_case_id: test_case_id,
          status: "failure",
          ran_at: base,
          inserted_at: base
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{
            "threshold" => 85,
            "window_type" => "rolling",
            "rolling_window_size" => 10,
            "comparison" => "lt"
          }
        )

      # Last 10 distinct runs hold 1 failure → 90% reliable, above the 85%
      # threshold. Counting the re-inserted failure three times reports
      # 7/10 = 70% and wrongly skips a healthy test.
      refute test_case_id in FlakyTestsMonitor.evaluate_by_reliability_rate(alert).triggered
    end

    test "a 75-run window remains exact with all 25 correction positions in use" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "correction_headroom")

      base = NaiveDateTime.utc_now()

      stable_runs =
        Enum.map(1..74, fn offset ->
          aggregate_run_attrs(project.id, test_case_id, NaiveDateTime.add(base, -offset, :second))
        end)

      corrected_run_id = UUIDv7.generate()

      corrected_run_rows =
        Enum.map(0..25, fn correction ->
          aggregate_run_attrs(project.id, test_case_id, base,
            id: corrected_run_id,
            is_flaky: correction > 0
          )
        end)

      IngestRepo.insert_all(TestCaseRun, stable_runs ++ corrected_run_rows)

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 2,
            "window_type" => "rolling",
            "rolling_window_size" => 75,
            "comparison" => "gte"
          }
        )

      # The active 100-position aggregate still contains all 75 distinct runs.
      # The corrected run counts once, so the rate is 1/75 rather than 26/75.
      refute test_case_id in FlakyTestsMonitor.evaluate(alert).triggered
    end
  end

  # One flaky run (most recent), re-inserted the way flaky detection does: the
  # original ingestion writes is_flaky=false, then later re-marks re-insert the
  # SAME run (same id + ran_at) with is_flaky=true. Preceded by four older
  # stable runs.
  # Every rolling window is served by `test_case_runs_recent_window_per_case`,
  # which encodes each run as a single Int64. These run against real ClickHouse
  # so the packing, the bit-level flag reads, and the de-duplication of
  # correction rows are exercised as ClickHouse actually evaluates them.
  describe "rolling window measurement" do
    test "flakiness_rate measures the packed aggregate" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "packed_flaky")

      base = NaiveDateTime.utc_now()

      # 100 runs, every tenth flaky → 10%.
      for i <- 1..100 do
        ran_at = NaiveDateTime.add(base, -i, :second)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: rem(i, 10) == 0,
          status: if(rem(i, 10) == 0, do: "failure", else: "success"),
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      triggered = fn threshold ->
        alert =
          AutomationsFixtures.automation_alert_fixture(
            project: project,
            monitor_type: "flakiness_rate",
            trigger_config: %{
              "threshold" => threshold,
              "window_type" => "rolling",
              "rolling_window_size" => 100,
              "comparison" => "gte"
            }
          )

        test_case_id in FlakyTestsMonitor.evaluate(alert).triggered
      end

      assert triggered.(10)
      refute triggered.(11)
    end

    test "reliability_rate reads the success bit of the same packed entry" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "packed_unreliable")

      base = NaiveDateTime.utc_now()

      # 80 of 100 runs succeed → 80% reliability.
      for i <- 1..100 do
        ran_at = NaiveDateTime.add(base, -i, :second)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: if(rem(i, 5) == 0, do: "failure", else: "success"),
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{
            "threshold" => 85,
            "window_type" => "rolling",
            "rolling_window_size" => 100,
            "comparison" => "lt"
          }
        )

      assert test_case_id in FlakyTestsMonitor.evaluate_by_reliability_rate(alert).triggered
    end

    test "counts a re-inserted flaky run once" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "packed_corrected")

      base = NaiveDateTime.utc_now()

      for i <- 1..99 do
        ran_at = NaiveDateTime.add(base, -i, :second)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: false,
          status: "success",
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # One logical run re-inserted as flaky, exactly as the correction path
      # writes it. Both physical rows share `ran_at`, so they share a packed run
      # key and differ only in the flag bits.
      corrected_run_id = UUIDv7.generate()

      for is_flaky <- [false, true] do
        RunsFixtures.test_case_run_fixture(
          id: corrected_run_id,
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: is_flaky,
          status: "failure",
          ran_at: base,
          inserted_at: base
        )
      end

      alert = fn threshold ->
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => threshold,
            "window_type" => "rolling",
            "rolling_window_size" => 100,
            "comparison" => "gte"
          }
        )
      end

      # The correction is kept, so the run counts as flaky exactly once.
      assert test_case_id in FlakyTestsMonitor.evaluate_by_run_count(alert.(1)).triggered
      refute test_case_id in FlakyTestsMonitor.evaluate_by_run_count(alert.(2)).triggered
    end

    test "does not evaluate a small window the aggregate has not filled yet" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "packed_partial_small")

      base = NaiveDateTime.utc_now()

      # Three flaky runs against a ten-run window. A partial window would report
      # 100%; the alert asked about ten runs, and only three exist.
      for i <- 1..3 do
        ran_at = NaiveDateTime.add(base, -i, :second)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: true,
          status: "failure",
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 50,
            "window_type" => "rolling",
            "rolling_window_size" => 10,
            "comparison" => "gte"
          }
        )

      refute test_case_id in FlakyTestsMonitor.evaluate(alert).triggered
    end

    test "does not evaluate a large window the aggregate has not filled yet" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "packed_partial")

      base = NaiveDateTime.utc_now()

      # Every run is flaky, so a partial window would report 100% and quarantine
      # the test on the strength of 20 runs when the user asked about 300.
      for i <- 1..20 do
        ran_at = NaiveDateTime.add(base, -i, :second)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: true,
          status: "failure",
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => 50,
            "window_type" => "rolling",
            "rolling_window_size" => 300,
            "comparison" => "gte"
          }
        )

      refute test_case_id in FlakyTestsMonitor.evaluate(alert).triggered
    end

    test "evaluate_rolling_alerts/2 measures the packed aggregate for a shared window" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "packed_grouped")

      base = NaiveDateTime.utc_now()

      for i <- 1..100 do
        ran_at = NaiveDateTime.add(base, -i, :second)

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          is_flaky: rem(i, 4) == 0,
          status: if(rem(i, 4) == 0, do: "failure", else: "success"),
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      alert_for = fn threshold ->
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{
            "threshold" => threshold,
            "window_type" => "rolling",
            "rolling_window_size" => 100,
            "comparison" => "gte"
          }
        )
      end

      firing = alert_for.(25)
      quiet = alert_for.(26)

      triggered_by_alert_id =
        FlakyTestsMonitor.evaluate_rolling_alerts([firing, quiet], [test_case_id])

      assert Map.fetch!(triggered_by_alert_id, firing.id) == [test_case_id]
      assert Map.fetch!(triggered_by_alert_id, quiet.id) == []
    end
  end

  defp insert_run_with_reinserted_flaky_tail(project_id, test_case_id) do
    base = NaiveDateTime.utc_now()

    for i <- 1..4 do
      ran_at = NaiveDateTime.add(base, -i, :minute)

      RunsFixtures.test_case_run_fixture(
        project_id: project_id,
        test_case_id: test_case_id,
        is_flaky: false,
        ran_at: ran_at,
        inserted_at: ran_at
      )
    end

    flaky_run_id = UUIDv7.generate()

    for is_flaky <- [false, true, true] do
      RunsFixtures.test_case_run_fixture(
        id: flaky_run_id,
        project_id: project_id,
        test_case_id: test_case_id,
        is_flaky: is_flaky,
        ran_at: base,
        inserted_at: base
      )
    end
  end

  defp with_read_repo(fun) do
    previous_dynamic_repo = ClickHouseRepo.get_dynamic_repo()

    try do
      # ClickHouse exposes parts inserted by the sandboxed write connection to
      # the separate read connection before the surrounding transaction ends.
      ClickHouseRepo.put_dynamic_repo(ClickHouseRepo)
      fun.()
    after
      ClickHouseRepo.put_dynamic_repo(previous_dynamic_repo)
    end
  end

  defp aggregate_run_attrs(project_id, test_case_id, ran_at, overrides \\ []) do
    Map.merge(
      %{
        id: UUIDv7.generate(),
        test_run_id: UUIDv7.generate(),
        test_module_run_id: UUIDv7.generate(),
        test_case_id: test_case_id,
        project_id: project_id,
        is_ci: false,
        scheme: "",
        git_branch: "main",
        git_commit_sha: "",
        module_name: "MyTests",
        suite_name: "TestSuite",
        name: "testExample",
        status: 0,
        is_flaky: false,
        is_new: false,
        is_quarantined: false,
        duration: 100,
        ran_at: ran_at,
        inserted_at: ran_at
      },
      Map.new(overrides)
    )
  end

  describe "branch_scope/1" do
    test "reliability defaults to the default branch and flakiness to every branch" do
      project = ProjectsFixtures.project_fixture()

      reliability =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d"}
        )

      flakiness =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 10, "window_type" => "last_days", "window" => "30d"}
        )

      assert FlakyTestsMonitor.branch_scope(reliability) == :default_branch
      assert FlakyTestsMonitor.branch_scope(flakiness) == :all_branches
    end

    test "alerts that read different buckets are not collapsed into one rolling query" do
      project = ProjectsFixtures.project_fixture()

      base = %{"threshold" => 90, "window_type" => "rolling", "rolling_window_size" => 10}

      scoped =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: base
        )

      unscoped =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: base
        )

      refute FlakyTestsMonitor.rolling_group_key(scoped) == FlakyTestsMonitor.rolling_group_key(unscoped)
    end
  end

  describe "default-branch scoping" do
    test "a reliability alert ignores failures that only happened off the default branch" do
      project = ProjectsFixtures.project_fixture()

      # Ten passing trunk runs clear the sample floor and put this test case at
      # 100% on the default branch. The four failures on a pull-request branch
      # would drag it to 71% measured across every branch, under the 90%
      # threshold.
      for _ <- 1..10, do: run_test_case(project, "main", "success")
      for _ <- 1..4, do: run_test_case(project, "feature/wip", "failure")

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      scoped =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d"}
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_reliability_rate(scoped)

      # The failures are still on record; it is the scoping that excluded them,
      # not the runs having gone missing.
      assert aggregate_runs("test_case_run_daily_stats_per_case", project.id, test_case.id) ==
               {14, 10}

      assert aggregate_runs("test_case_run_daily_stats_per_case_default_branch", project.id, test_case.id) ==
               {10, 10}
    end

    test "a reliability alert does not act on a trunk sample too small to describe" do
      project = ProjectsFixtures.project_fixture()

      # One failing trunk run is 0% reliable, which trips any threshold. The
      # calendar window has no natural minimum, so without the sample floor this
      # would quarantine a test on a single run — and every project starts here,
      # since nothing backfills the scoped aggregate.
      run_test_case(project, "main", "failure")

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d"}
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_reliability_rate(alert)
      assert FlakyTestsMonitor.measurable_test_case_ids(alert, [test_case.id]) == []

      # It becomes measurable, and fires, once the window holds enough runs.
      for _ <- 1..9, do: run_test_case(project, "main", "failure")

      assert FlakyTestsMonitor.measurable_test_case_ids(alert, [test_case.id]) == [test_case.id]
      assert %{triggered: [triggered_id]} = FlakyTestsMonitor.evaluate_by_reliability_rate(alert)
      assert triggered_id == test_case.id
    end

    test "a project whose default branch is master scopes to master, not to main" do
      project = ProjectsFixtures.project_fixture()
      {:ok, project} = Tuist.Projects.update_project(project, %{default_branch: "master"})

      for _ <- 1..10, do: run_test_case(project, "master", "success")
      for _ <- 1..4, do: run_test_case(project, "main", "failure")

      scoped =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d"}
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_reliability_rate(scoped)
    end

    test "a rolling reliability window counts only default-branch runs toward being filled" do
      project = ProjectsFixtures.project_fixture()

      # Two default-branch runs and four off-branch ones. A window of three is
      # filled across every branch but not on the trunk, so the scoped alert has
      # nothing it is willing to measure yet.
      for _ <- 1..2, do: run_test_case(project, "main", "success")
      for _ <- 1..4, do: run_test_case(project, "feature/wip", "failure")

      scoped =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "rolling", "rolling_window_size" => 3}
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_reliability_rate(scoped)

      run_test_case(project, "main", "success")

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_reliability_rate(scoped)
    end

    test "flakiness keeps measuring every branch unless the alert opts in" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "flakes_on_prs")

      # The only run this test case has flaked on a pull-request branch. A
      # default-branch-scoped alert would see nothing; flakiness is not scoped,
      # so it sees the flake wherever it happened.
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "feature/wip",
        status: "failure",
        is_flaky: true
      )

      unscoped =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 50, "window_type" => "last_days", "window" => "30d"}
        )

      assert %{triggered: [^test_case_id]} = FlakyTestsMonitor.evaluate(unscoped)
    end
  end

  describe "measurable_test_case_ids/2" do
    test "a flakiness alert measures everything it is asked about" do
      project = ProjectsFixtures.project_fixture()
      ids = [UUIDv7.generate(), UUIDv7.generate()]

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 10, "window_type" => "last_days", "window" => "30d"}
        )

      assert FlakyTestsMonitor.measurable_test_case_ids(alert, ids) == ids
    end

    test "a scoped alert cannot measure a test case with no default-branch runs" do
      project = ProjectsFixtures.project_fixture()

      run_test_case(project, "feature/wip", "failure")
      {[off_branch_only], _meta} = Tests.list_test_cases(project.id, %{})

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d"}
        )

      assert FlakyTestsMonitor.measurable_test_case_ids(alert, [off_branch_only.id]) == []
    end

    test "a scoped alert measures a test case once it has run on the default branch" do
      project = ProjectsFixtures.project_fixture()

      for _ <- 1..10, do: run_test_case(project, "main", "success")
      {[on_branch], _meta} = Tests.list_test_cases(project.id, %{})

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "window_type" => "last_days", "window" => "30d"}
        )

      assert FlakyTestsMonitor.measurable_test_case_ids(alert, [on_branch.id]) == [on_branch.id]
    end
  end

  defp run_test_case(project, git_branch, status, opts \\ []) do
    {:ok, run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        git_branch: git_branch,
        is_ci: true,
        test_modules: [
          %{
            name: "M",
            status: status,
            duration: 1000,
            test_cases: [
              Enum.into(opts, %{name: "subject", status: status, duration: 100})
            ]
          }
        ]
      )

    run
  end

  # Returns {run_count, successful_run_count} straight out of an aggregate, so a
  # test can show which runs a table actually holds rather than inferring it from
  # whether an alert fired.
  defp aggregate_runs(table, project_id, test_case_id) do
    %{rows: [[runs, successes]]} =
      IngestRepo.query!(
        """
        SELECT countMerge(run_count), sumMerge(successful_run_count)
        FROM #{table}
        WHERE project_id = {project_id:Int64} AND test_case_id = {test_case_id:UUID}
        """,
        %{project_id: project_id, test_case_id: test_case_id}
      )

    {runs, successes}
  end
end
