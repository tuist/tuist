defmodule Tuist.Automations.MatchCountTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "counts the same eligible matches as the baseline without applying actions or changing it" do
    alert =
      AutomationsFixtures.automation_alert_fixture(
        baseline_established_at: nil,
        trigger_config: %{"threshold" => 10, "window_type" => "last_days", "window" => "30d", "states" => ["muted"]}
      )

    cases =
      Enum.map(["muted", "enabled", "muted"], fn state ->
        IngestRepo.insert!(RunsFixtures.test_case_fixture(project_id: alert.project_id, state: state))
      end)

    [eligible, wrong_state, unvalidated] = cases
    ids = Enum.map(cases, & &1.id)

    stub(FlakyTestsMonitor, :evaluate, fn _alert, batch ->
      assert Enum.sort(batch) == Enum.sort(ids)
      %{triggered: ids ++ ids}
    end)

    stub(Tests, :test_case_ids_with_successful_default_branch_run, fn project_id, ^ids, _branch ->
      assert project_id == alert.project_id
      [eligible.id, wrong_state.id]
    end)

    stub(ActionExecutor, :execute_actions, fn _, _, _ -> flunk("A preview must not execute actions") end)

    assert Automations.count_existing_matches(alert) == 1
    assert Automations.matching_test_case_ids(alert, ids) == [eligible.id]
    refute unvalidated.id in Automations.matching_test_case_ids(alert, ids)
    assert Repo.reload!(alert) == alert
  end

  test "legacy and event-driven monitors produce an empty baseline match set" do
    alert = AutomationsFixtures.automation_alert_fixture()

    for metric <- ["retired_monitor", "test_updated"] do
      assert Automations.matching_test_case_ids(%{alert | monitor_type: metric}, [Ecto.UUID.generate()], "main") == []
    end
  end

  for {metric, evaluator} <- [
        {"flakiness_rate", :evaluate},
        {"flaky_run_count", :evaluate_by_run_count},
        {"reliability_rate", :evaluate_by_reliability_rate}
      ] do
    test "counts #{metric} in bounded pages" do
      alert = AutomationsFixtures.automation_alert_fixture(monitor_type: unquote(metric))
      project = Projects.get_project_by_id(alert.project_id)

      expect(Projects, :get_project_by_id, fn project_id ->
        assert project_id == alert.project_id
        project
      end)

      now = NaiveDateTime.utc_now()

      cases =
        Enum.map(1..2001, fn index ->
          %{
            id: Ecto.UUID.generate(),
            name: "test#{index}",
            module_name: "Tests",
            suite_name: "Preview",
            project_id: alert.project_id,
            last_status: "success",
            last_duration: 1,
            last_ran_at: now,
            inserted_at: now,
            recent_durations: [1],
            avg_duration: 1
          }
        end)

      IngestRepo.insert_all(TestCase, cases)
      test_pid = self()

      stub(FlakyTestsMonitor, unquote(evaluator), fn _alert, ids ->
        send(test_pid, {:batch_size, length(ids)})
        %{triggered: ids ++ ids}
      end)

      stub(Tests, :test_case_ids_with_successful_default_branch_run, fn _, ids, _ -> ids end)

      assert Automations.count_existing_matches(alert) == 2001
      assert_receive {:batch_size, 2000}
      assert_receive {:batch_size, 1}
      refute_receive {:batch_size, _}
    end
  end
end
