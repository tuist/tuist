defmodule Tuist.Automations.Monitors.FlakyTestsMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.FlakyTestsMonitor
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

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: "failure"
      )

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
            "rolling_window_size" => 5,
            "comparison" => "gte"
          }
        )

      triggered = FlakyTestsMonitor.evaluate_by_run_count(alert, [included_id]).triggered

      assert included_id in triggered
      refute excluded_id in triggered
    end

    test "uses the 250-run aggregate for a 247-run window" do
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

      insert_test_case_runs([
        test_case_run_attrs(project.id, test_case.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -1, :hour),
          inserted_at: NaiveDateTime.add(base, -1, :hour)
        )
        | for i <- 1..245 do
            test_case_run_attrs(project.id, test_case.id,
              is_flaky: false,
              ran_at: NaiveDateTime.add(base, i, :second),
              inserted_at: NaiveDateTime.add(base, i, :second)
            )
          end
      ])

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 247,
            "comparison" => "gte"
          }
        )

      assert test_case.id in FlakyTestsMonitor.evaluate_by_run_count(alert).triggered
    end

    test "uses the 1000-run aggregate above the recent-runs bucket cap" do
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

      insert_test_case_runs([
        test_case_run_attrs(project.id, test_case.id,
          is_flaky: true,
          ran_at: NaiveDateTime.add(base, -1, :hour),
          inserted_at: NaiveDateTime.add(base, -1, :hour)
        )
        | for i <- 1..749 do
            test_case_run_attrs(project.id, test_case.id,
              is_flaky: false,
              ran_at: NaiveDateTime.add(base, i, :second),
              inserted_at: NaiveDateTime.add(base, i, :second)
            )
          end
      ])

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{
            "threshold" => 1,
            "window_type" => "rolling",
            "rolling_window_size" => 751,
            "comparison" => "gte"
          }
        )

      assert test_case.id in FlakyTestsMonitor.evaluate_by_run_count(alert).triggered
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

    test "reads a mid-size bucket and ignores runs older than the window" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "rolling_mid_bucket")

      base = NaiveDateTime.utc_now()

      # Older history is all failures; a 247-run window routes to the 250-run
      # bucket and must see only the recent successes, so reliability is 100%
      # and the alert (unreliable when < 90%) does not fire. Reading the full
      # history instead would drop it to ~45% and wrongly trigger.
      old_failures =
        for i <- 1..300 do
          test_case_run_attrs(project.id, test_case_id,
            status: 1,
            ran_at: NaiveDateTime.add(base, -10_000 - i, :second),
            inserted_at: NaiveDateTime.add(base, -10_000 - i, :second)
          )
        end

      recent_successes =
        for i <- 1..247 do
          test_case_run_attrs(project.id, test_case_id,
            status: 0,
            ran_at: NaiveDateTime.add(base, i, :second),
            inserted_at: NaiveDateTime.add(base, i, :second)
          )
        end

      insert_test_case_runs(old_failures ++ recent_successes)

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{
            "threshold" => 90,
            "window_type" => "rolling",
            "rolling_window_size" => 247,
            "comparison" => "lt"
          }
        )

      refute test_case_id in FlakyTestsMonitor.evaluate_by_reliability_rate(alert).triggered
    end

    test "falls back to the 1000-run aggregate above the bucket cap" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      RunsFixtures.test_case_fixture(project_id: project.id, id: test_case_id, name: "rolling_above_cap")

      base = NaiveDateTime.utc_now()

      # A 751-run window is above the largest bucket (750), so evaluation reads
      # the full `recent_successful_runs` aggregate. All-failure runs give 0%
      # reliability, which trips the < 90% threshold.
      failures =
        for i <- 1..750 do
          test_case_run_attrs(project.id, test_case_id,
            status: 1,
            ran_at: NaiveDateTime.add(base, i, :second),
            inserted_at: NaiveDateTime.add(base, i, :second)
          )
        end

      insert_test_case_runs(failures)

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{
            "threshold" => 90,
            "window_type" => "rolling",
            "rolling_window_size" => 751,
            "comparison" => "lt"
          }
        )

      assert test_case_id in FlakyTestsMonitor.evaluate_by_reliability_rate(alert).triggered
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
  end

  # One flaky run (most recent), re-inserted the way flaky detection does: the
  # original ingestion writes is_flaky=false, then later re-marks re-insert the
  # SAME run (same id + ran_at) with is_flaky=true. Preceded by four older
  # stable runs.
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

  defp insert_test_case_runs(rows) do
    IngestRepo.insert_all(TestCaseRun, rows)
  end

  defp test_case_run_attrs(project_id, test_case_id, attrs) do
    %{
      id: UUIDv7.generate(),
      test_run_id: UUIDv7.generate(),
      test_module_run_id: UUIDv7.generate(),
      test_case_id: test_case_id,
      project_id: project_id,
      account_id: Keyword.get(attrs, :account_id),
      is_ci: Keyword.get(attrs, :is_ci, false),
      scheme: Keyword.get(attrs, :scheme, ""),
      git_branch: Keyword.get(attrs, :git_branch, "main"),
      git_commit_sha: Keyword.get(attrs, :git_commit_sha, ""),
      module_name: Keyword.get(attrs, :module_name, "MyTests"),
      suite_name: Keyword.get(attrs, :suite_name, "TestSuite"),
      name: Keyword.get(attrs, :name, "testExample"),
      status: Keyword.get(attrs, :status, 0),
      is_flaky: Keyword.get(attrs, :is_flaky, false),
      is_new: Keyword.get(attrs, :is_new, false),
      is_quarantined: Keyword.get(attrs, :is_quarantined, false),
      duration: Keyword.get(attrs, :duration, 100),
      ran_at: Keyword.fetch!(attrs, :ran_at),
      inserted_at: Keyword.fetch!(attrs, :inserted_at)
    }
  end
end
