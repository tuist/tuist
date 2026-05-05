defmodule Tuist.Automations.Monitors.FlakyTestsMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "evaluate/1 with lt comparison" do
    test "fires for flagged tests with rate below threshold" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "stale", status: "success", duration: 100}]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})
      {:ok, _} = Tests.update_test_case(test_case.id, %{is_flaky: true})

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 5, "window" => "1h", "comparison" => "lt"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate(alert)
      assert triggered == [test_case.id]
    end

    test "skips flagged tests whose rate meets the threshold" do
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
      {:ok, _} = Tests.update_test_case(test_case.id, %{is_flaky: true})

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

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case.id,
          is_flaky: false,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 10, "window" => "30d", "comparison" => "lt"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate(alert)
    end

    test "ignores tests that are not flagged" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "healthy", status: "success", duration: 100}]
            }
          ]
        )

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 5, "window" => "30d", "comparison" => "lt"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate(alert)
    end
  end

  describe "evaluate_by_run_count/1 with lt comparison" do
    test "fires for flagged tests with no flaky runs in the window" do
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
                %{name: "stale_flaky", status: "success", duration: 100},
                %{name: "stable", status: "success", duration: 100}
              ]
            }
          ]
        )

      {test_cases, _meta} = Tests.list_test_cases(project.id, %{})
      stale = Enum.find(test_cases, &(&1.name == "stale_flaky"))

      {:ok, _} = Tests.update_test_case(stale.id, %{is_flaky: true})

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 1, "window" => "30d", "comparison" => "lt"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert triggered == [stale.id]
    end

    test "ignores tests that are not flagged regardless of how few flaky runs they have" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases: [%{name: "healthy", status: "success", duration: 100}]
            }
          ]
        )

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 100, "window" => "30d", "comparison" => "lt"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_run_count(alert)
    end

    test "skips flagged tests whose flaky run count meets the threshold" do
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
                %{name: "still_flaky", status: "success", duration: 100},
                %{name: "no_longer_flaky", status: "success", duration: 100}
              ]
            }
          ]
        )

      {test_cases, _meta} = Tests.list_test_cases(project.id, %{})
      still_flaky = Enum.find(test_cases, &(&1.name == "still_flaky"))
      no_longer_flaky = Enum.find(test_cases, &(&1.name == "no_longer_flaky"))

      {:ok, _} = Tests.update_test_case(still_flaky.id, %{is_flaky: true})
      {:ok, _} = Tests.update_test_case(no_longer_flaky.id, %{is_flaky: true})

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: still_flaky.id,
        is_flaky: true,
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: still_flaky.id,
        is_flaky: true,
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -2, :day)
      )

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 2, "window" => "30d", "comparison" => "lt"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert triggered == [no_longer_flaky.id]
    end
  end

  describe "evaluate_by_run_count/1 with gt comparison" do
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

      assert %{triggered: [triggered_id]} = FlakyTestsMonitor.evaluate_by_run_count(alert)
      assert triggered_id == test_case.id
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
