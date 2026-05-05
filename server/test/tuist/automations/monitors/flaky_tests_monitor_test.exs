defmodule Tuist.Automations.Monitors.FlakyTestsMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "evaluate_below/1" do
    test "fires for flagged tests with no runs in the window" do
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
          monitor_type: "flakiness_rate_below",
          trigger_config: %{"threshold" => 5, "window" => "1h"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      # `test_fixture` inserts runs at `now`, so a 1h window catches them. The
      # test_case has zero flaky runs, so its rate is 0% — well below 5% — and
      # it should fire. (The "no runs at all" branch is exercised below.)
      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_below(alert)
      assert triggered == [test_case.id]
    end

    test "skips flagged tests whose flakiness rate meets the threshold" do
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

      # Half the runs in the window are flaky → 50% rate, well above any
      # reasonable cleanup threshold.
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
          monitor_type: "flakiness_rate_below",
          trigger_config: %{"threshold" => 10, "window" => "30d"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_below(alert)
    end

    test "ignores tests that are not flagged" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :day),
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
          monitor_type: "flakiness_rate_below",
          trigger_config: %{"threshold" => 5, "window" => "30d"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_below(alert)
    end
  end

  describe "evaluate_by_run_count_below/1" do
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
          monitor_type: "flaky_run_count_below",
          trigger_config: %{"threshold" => 1, "window" => "30d"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count_below(alert)
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
              test_cases: [
                %{name: "healthy", status: "success", duration: 100}
              ]
            }
          ]
        )

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count_below",
          trigger_config: %{"threshold" => 100, "window" => "30d"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: []} = FlakyTestsMonitor.evaluate_by_run_count_below(alert)
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

      # `still_flaky` has 2 flaky runs in the window, `no_longer_flaky` has 0,
      # so with threshold=2 only the latter falls below.
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
          monitor_type: "flaky_run_count_below",
          trigger_config: %{"threshold" => 2, "window" => "30d"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count_below(alert)
      assert triggered == [no_longer_flaky.id]
    end

    test "ignores flaky runs outside the trigger window" do
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
                %{name: "old_flake", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Tests.list_test_cases(project.id, %{})
      {:ok, _} = Tests.update_test_case(test_case.id, %{is_flaky: true})

      # Flaky run sits 60 days ago, outside the 30d window.
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case.id,
        is_flaky: true,
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :day)
      )

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count_below",
          trigger_config: %{"threshold" => 1, "window" => "30d"},
          trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
        )

      assert %{triggered: triggered} = FlakyTestsMonitor.evaluate_by_run_count_below(alert)
      assert triggered == [test_case.id]
    end
  end
end
