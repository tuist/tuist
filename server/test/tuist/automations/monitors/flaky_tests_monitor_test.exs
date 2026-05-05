defmodule Tuist.Automations.Monitors.FlakyTestsMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Tests
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
          trigger_config: %{"threshold" => 5, "window" => "1d", "comparison" => "lt"}
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
          trigger_config: %{"threshold" => 5, "window" => "30d", "comparison" => "lt"}
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
          trigger_config: %{"threshold" => 50, "window" => "30d", "comparison" => "lt"}
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
          trigger_config: %{"threshold" => 2, "window" => "30d", "comparison" => "lt"}
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
          trigger_config: %{"threshold" => 2, "window" => "30d", "comparison" => "gt"}
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
          trigger_config: %{"threshold" => 3, "window" => "30d"}
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert test_case.id in triggered
    end
  end
end
