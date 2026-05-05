defmodule Tuist.Automations.Workers.AlertEvaluationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  defp run(alert_id) do
    AlertEvaluationWorker.perform(%Oban.Job{args: %{"alert_id" => alert_id}})
  end

  test "no-op when automation is missing" do
    reject(&FlakyTestsMonitor.evaluate/1)
    assert :ok = run(UUIDv7.generate())
  end

  test "no-op when automation is disabled" do
    automation = AutomationsFixtures.automation_alert_fixture(enabled: false)
    reject(&FlakyTestsMonitor.evaluate/1)
    assert :ok = run(automation.id)
  end

  test "executes trigger actions for newly triggered test cases and creates alert" do
    automation =
      AutomationsFixtures.automation_alert_fixture(trigger_actions: [%{"type" => "change_state", "state" => "muted"}])

    triggered_id = Ecto.UUID.generate()

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [triggered_id], all: [triggered_id]}
    end)

    expect(Automations, :list_active_alert_events, fn _id -> [] end)

    expected_entity = %{type: :test_case, id: triggered_id}

    expect(ActionExecutor, :execute_actions, fn actions, ^automation, ^expected_entity ->
      assert actions == automation.trigger_actions
      :ok
    end)

    expect(Automations, :create_alert_event, fn %{alert_id: id, test_case_id: tc, status: "triggered"} ->
      assert id == automation.id
      assert tc == triggered_id
      :ok
    end)

    assert :ok = run(automation.id)
  end

  test "skips test cases that already have an active alert" do
    automation = AutomationsFixtures.automation_alert_fixture()
    already = Ecto.UUID.generate()

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [already], all: [already]}
    end)

    expect(Automations, :list_active_alert_events, fn _id ->
      [%{test_case_id: already, triggered_at: NaiveDateTime.utc_now()}]
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    assert :ok = run(automation.id)
  end

  test "executes recovery actions and resolves alert when condition clears" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        recovery_enabled: true,
        recovery_config: %{"window" => "1d"},
        recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
      )

    recovered_id = Ecto.UUID.generate()

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [], all: [recovered_id]}
    end)

    triggered_long_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day)

    expect(Automations, :list_active_alert_events, fn _id ->
      [%{test_case_id: recovered_id, triggered_at: triggered_long_ago}]
    end)

    expected_entity = %{type: :test_case, id: recovered_id}

    expect(ActionExecutor, :execute_actions, fn actions, ^automation, ^expected_entity ->
      assert actions == automation.recovery_actions
      :ok
    end)

    expect(Automations, :create_alert_event, fn %{
                                                  alert_id: id,
                                                  test_case_id: ^recovered_id,
                                                  status: "recovered"
                                                } ->
      assert id == automation.id
      :ok
    end)

    assert :ok = run(automation.id)
  end

  test "does not run recovery actions when window has not elapsed" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        recovery_enabled: true,
        recovery_config: %{"window" => "14d"}
      )

    recovered_id = Ecto.UUID.generate()

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [], all: [recovered_id]}
    end)

    triggered_recently = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

    expect(Automations, :list_active_alert_events, fn _id ->
      [%{test_case_id: recovered_id, triggered_at: triggered_recently}]
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    assert :ok = run(automation.id)
  end

  test "does not run recovery when recovery_enabled is false" do
    automation = AutomationsFixtures.automation_alert_fixture(recovery_enabled: false)

    expect(FlakyTestsMonitor, :evaluate, fn _automation -> %{triggered: [], all: []} end)
    expect(Automations, :list_active_alert_events, fn _id -> [] end)
    reject(&Automations.create_alert_event/1)

    assert :ok = run(automation.id)
  end

  test "dispatches lt-comparison alerts to the metric's evaluator" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 1, "window" => "30d", "comparison" => "lt"},
        trigger_actions: [%{"type" => "remove_label", "label" => "flaky"}]
      )

    cleanup_id = Ecto.UUID.generate()

    reject(&FlakyTestsMonitor.evaluate/1)

    expect(FlakyTestsMonitor, :evaluate_by_run_count, fn ^automation ->
      %{triggered: [cleanup_id], all: [cleanup_id]}
    end)

    expect(Automations, :list_active_alert_events, fn _id -> [] end)

    expected_entity = %{type: :test_case, id: cleanup_id}

    expect(ActionExecutor, :execute_actions, fn actions, ^automation, ^expected_entity ->
      assert actions == automation.trigger_actions
      :ok
    end)

    expect(Automations, :create_alert_event, fn %{
                                                  alert_id: id,
                                                  test_case_id: ^cleanup_id,
                                                  status: "triggered"
                                                } ->
      assert id == automation.id
      :ok
    end)

    assert :ok = run(automation.id)
  end
end
