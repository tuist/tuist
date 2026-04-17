defmodule Tuist.Automations.Workers.AutomationEvaluationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Types.FlakinessRateType
  alias Tuist.Automations.Workers.AutomationEvaluationWorker
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  defp run(automation_id) do
    AutomationEvaluationWorker.perform(%Oban.Job{args: %{"automation_id" => automation_id}})
  end

  test "no-op when automation is missing" do
    reject(&FlakinessRateType.evaluate/1)
    assert :ok = run(UUIDv7.generate())
  end

  test "no-op when automation is disabled" do
    automation = AutomationsFixtures.automation_fixture(enabled: false)
    reject(&FlakinessRateType.evaluate/1)
    assert :ok = run(automation.id)
  end

  test "executes trigger actions for newly triggered test cases and inserts state" do
    automation =
      AutomationsFixtures.automation_fixture(trigger_actions: [%{"type" => "change_state", "state" => "muted"}])

    triggered_id = Ecto.UUID.generate()

    expect(FlakinessRateType, :evaluate, fn _automation ->
      %{triggered: [triggered_id], all: [triggered_id]}
    end)

    expect(Automations, :list_triggers, fn _id -> [] end)

    expected_entity = %{type: :test_case, id: triggered_id}

    expect(ActionExecutor, :execute_actions, fn actions, ^automation, ^expected_entity ->
      assert actions == automation.trigger_actions
      :ok
    end)

    expect(Automations, :insert_trigger, fn %{automation_id: id, test_case_id: tc, status: "triggered"} ->
      assert id == automation.id
      assert tc == triggered_id
      :ok
    end)

    assert :ok = run(automation.id)
  end

  test "skips test cases that already have a triggered state" do
    automation = AutomationsFixtures.automation_fixture()
    already = Ecto.UUID.generate()

    expect(FlakinessRateType, :evaluate, fn _automation ->
      %{triggered: [already], all: [already]}
    end)

    expect(Automations, :list_triggers, fn _id ->
      [%{test_case_id: already, triggered_at: NaiveDateTime.utc_now()}]
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.insert_trigger/1)

    assert :ok = run(automation.id)
  end

  test "executes recovery actions when condition no longer holds and recovery window elapsed" do
    automation =
      AutomationsFixtures.automation_fixture(
        recovery_enabled: true,
        recovery_config: %{"window" => "1d"},
        recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
      )

    recovered_id = Ecto.UUID.generate()

    expect(FlakinessRateType, :evaluate, fn _automation ->
      %{triggered: [], all: [recovered_id]}
    end)

    triggered_long_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day)

    expect(Automations, :list_triggers, fn _id ->
      [%{test_case_id: recovered_id, triggered_at: triggered_long_ago}]
    end)

    expected_entity = %{type: :test_case, id: recovered_id}

    expect(ActionExecutor, :execute_actions, fn actions, ^automation, ^expected_entity ->
      assert actions == automation.recovery_actions
      :ok
    end)

    expect(Automations, :mark_recovered, fn id, ^recovered_id ->
      assert id == automation.id
      :ok
    end)

    assert :ok = run(automation.id)
  end

  test "does not run recovery actions when window has not elapsed" do
    automation =
      AutomationsFixtures.automation_fixture(
        recovery_enabled: true,
        recovery_config: %{"window" => "14d"}
      )

    recovered_id = Ecto.UUID.generate()

    expect(FlakinessRateType, :evaluate, fn _automation ->
      %{triggered: [], all: [recovered_id]}
    end)

    triggered_recently = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

    expect(Automations, :list_triggers, fn _id ->
      [%{test_case_id: recovered_id, triggered_at: triggered_recently}]
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.mark_recovered/2)

    assert :ok = run(automation.id)
  end

  test "does not run recovery when recovery_enabled is false" do
    automation = AutomationsFixtures.automation_fixture(recovery_enabled: false)

    expect(FlakinessRateType, :evaluate, fn _automation -> %{triggered: [], all: []} end)
    expect(Automations, :list_triggers, fn _id -> [] end)
    reject(&Automations.mark_recovered/2)

    assert :ok = run(automation.id)
  end
end
