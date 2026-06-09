defmodule Tuist.Automations.Workers.AlertEvaluationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  setup do
    # By default, treat every triggered test case as validated on the default
    # branch so the existing transition/recovery assertions are unaffected.
    # Tests exercising the new-test exclusion override this stub.
    stub(Tests, :test_case_ids_with_successful_default_branch_run, fn _project_id, ids, _branch -> ids end)
    :ok
  end

  defp run(alert_id) do
    AlertEvaluationWorker.perform(%Oban.Job{args: %{"alert_id" => alert_id}})
  end

  defp run_scoped(alert_id, test_case_ids) do
    AlertEvaluationWorker.perform(%Oban.Job{args: %{"alert_id" => alert_id, "test_case_ids" => test_case_ids}})
  end

  defp run_recent_test_case_runs(alert_id) do
    AlertEvaluationWorker.perform(%Oban.Job{args: %{"alert_id" => alert_id, "evaluate_recent_test_case_runs" => true}})
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

  test "scoped jobs evaluate and diff only the affected test cases" do
    automation =
      AutomationsFixtures.automation_alert_fixture(trigger_actions: [%{"type" => "change_state", "state" => "muted"}])

    affected_id = Ecto.UUID.generate()

    reject(&FlakyTestsMonitor.evaluate/1)

    expect(FlakyTestsMonitor, :evaluate, fn ^automation, [^affected_id] ->
      %{triggered: [affected_id], all: [affected_id]}
    end)

    expect(Automations, :list_active_alert_events, fn id, [^affected_id] ->
      assert id == automation.id
      []
    end)

    expected_entity = %{type: :test_case, id: affected_id}

    expect(ActionExecutor, :execute_actions, fn actions, ^automation, ^expected_entity ->
      assert actions == automation.trigger_actions
      :ok
    end)

    expect(Automations, :create_alert_event, fn %{alert_id: id, test_case_id: tc, status: "triggered"} ->
      assert id == automation.id
      assert tc == affected_id
      :ok
    end)

    assert :ok = run_scoped(automation.id, [affected_id, "not-a-uuid", affected_id])
  end

  test "ingestion-driven job evaluates recently inserted test case ids and advances the cursor" do
    automation =
      AutomationsFixtures.automation_alert_fixture(trigger_actions: [%{"type" => "change_state", "state" => "muted"}])

    [first_id, second_id] = Enum.map(1..2, fn _ -> Ecto.UUID.generate() end)

    expect(ClickHouseRepo, :all, fn _query ->
      [
        %{test_case_id: first_id, last_inserted_at: ~N[2026-06-09 10:00:01]},
        %{test_case_id: second_id, last_inserted_at: ~N[2026-06-09 10:00:02]}
      ]
    end)

    reject(&FlakyTestsMonitor.evaluate/1)

    expect(FlakyTestsMonitor, :evaluate, fn ^automation, test_case_ids ->
      assert MapSet.new(test_case_ids) == MapSet.new([first_id, second_id])
      %{triggered: [], all: test_case_ids}
    end)

    expect(Automations, :list_active_alert_events, fn id, test_case_ids ->
      assert id == automation.id
      assert MapSet.new(test_case_ids) == MapSet.new([first_id, second_id])
      []
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    assert :ok = run_recent_test_case_runs(automation.id)

    assert {:ok, updated} = Automations.get_alert(automation.id)
    assert updated.last_scoped_evaluation_inserted_at == ~U[2026-06-09 10:00:02Z]
  end

  test "ingestion-driven job chunks large affected sets" do
    automation = AutomationsFixtures.automation_alert_fixture()
    test_case_ids = Enum.map(1..1001, fn _ -> Ecto.UUID.generate() end)
    test_pid = self()

    expect(ClickHouseRepo, :all, fn _query ->
      Enum.map(test_case_ids, fn test_case_id ->
        %{test_case_id: test_case_id, last_inserted_at: ~N[2026-06-09 10:00:00]}
      end)
    end)

    expect(FlakyTestsMonitor, :evaluate, 2, fn ^automation, chunk ->
      send(test_pid, {:monitor_chunk_size, length(chunk)})
      %{triggered: [], all: chunk}
    end)

    expect(Automations, :list_active_alert_events, 2, fn id, chunk ->
      assert id == automation.id
      send(test_pid, {:active_events_chunk_size, length(chunk)})
      []
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    assert :ok = run_recent_test_case_runs(automation.id)

    assert_receive {:monitor_chunk_size, 1000}
    assert_receive {:monitor_chunk_size, 1}
    assert_receive {:active_events_chunk_size, 1000}
    assert_receive {:active_events_chunk_size, 1}

    assert {:ok, updated} = Automations.get_alert(automation.id)
    assert updated.last_scoped_evaluation_inserted_at == ~U[2026-06-09 10:00:00Z]
  end

  test "ingestion-driven job no-ops when the alert is disabled" do
    automation = AutomationsFixtures.automation_alert_fixture()

    assert {:ok, disabled} = Automations.update_alert(automation, %{enabled: false})

    reject(&ClickHouseRepo.all/1)
    reject(&FlakyTestsMonitor.evaluate/1)
    reject(&FlakyTestsMonitor.evaluate/2)
    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    assert :ok = run_recent_test_case_runs(disabled.id)
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
        recovery_config: %{"window_type" => "last_days", "window" => "1d"},
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
        recovery_config: %{"window_type" => "last_days", "window" => "14d"}
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

  test "rolling recovery fires when enough new runs have followed the trigger" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        recovery_enabled: true,
        recovery_config: %{"window_type" => "rolling", "rolling_window_size" => 5},
        recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
      )

    recovered_id = Ecto.UUID.generate()

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [], all: [recovered_id]}
    end)

    expect(Automations, :list_active_alert_events, fn _id ->
      [%{test_case_id: recovered_id, triggered_at: NaiveDateTime.utc_now()}]
    end)

    # 7 runs have happened since the trigger, exceeds the rolling window of 5.
    expect(ClickHouseRepo, :all, fn _query ->
      now = NaiveDateTime.utc_now()
      Enum.map(1..7, fn i -> {recovered_id, NaiveDateTime.add(now, i, :second)} end)
    end)

    expected_entity = %{type: :test_case, id: recovered_id}
    expect(ActionExecutor, :execute_actions, fn _actions, ^automation, ^expected_entity -> :ok end)

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

  test "rolling recovery holds off until enough runs have followed the trigger" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        recovery_enabled: true,
        recovery_config: %{"window_type" => "rolling", "rolling_window_size" => 5}
      )

    recovered_id = Ecto.UUID.generate()

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [], all: [recovered_id]}
    end)

    expect(Automations, :list_active_alert_events, fn _id ->
      [%{test_case_id: recovered_id, triggered_at: NaiveDateTime.utc_now()}]
    end)

    # Only 2 runs since the trigger — below the rolling window of 5, so recovery
    # should not fire.
    expect(ClickHouseRepo, :all, fn _query ->
      now = NaiveDateTime.utc_now()
      Enum.map(1..2, fn i -> {recovered_id, NaiveDateTime.add(now, i, :second)} end)
    end)

    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    assert :ok = run(automation.id)
  end

  test "rolling recovery issues a single batched query for many active events" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        recovery_enabled: true,
        recovery_config: %{"window_type" => "rolling", "rolling_window_size" => 5}
      )

    ids = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)

    expect(FlakyTestsMonitor, :evaluate, fn _automation ->
      %{triggered: [], all: ids}
    end)

    expect(Automations, :list_active_alert_events, fn _id ->
      Enum.map(ids, fn id -> %{test_case_id: id, triggered_at: NaiveDateTime.utc_now()} end)
    end)

    # Exactly one ClickHouseRepo.all/1 call regardless of candidate count — no
    # N+1.
    expect(ClickHouseRepo, :all, 1, fn _query -> [] end)

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

  test "no-ops for event-driven test_updated alerts without invoking the monitor" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        monitor_type: "test_updated",
        trigger_config: %{"events" => ["marked_flaky"]}
      )

    reject(&FlakyTestsMonitor.evaluate/1)
    reject(&FlakyTestsMonitor.evaluate_by_run_count/1)
    reject(&ActionExecutor.execute_actions/3)
    reject(&Automations.create_alert_event/1)

    expect(Automations, :list_active_alert_events, fn _id -> [] end)

    assert :ok = run(automation.id)
  end

  describe "baseline establishment" do
    test "first evaluation records the matching set silently and stamps baseline_established_at" do
      automation = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)

      [tc1, tc2] = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      expect(FlakyTestsMonitor, :evaluate, fn _automation ->
        %{triggered: [tc1, tc2], all: [tc1, tc2]}
      end)

      # No trigger actions on the baseline path.
      reject(&ActionExecutor.execute_actions/3)

      # Both matching test cases get a `triggered` event so subsequent
      # evaluations skip them.
      expect(Automations, :create_alert_event, 2, fn %{
                                                       alert_id: id,
                                                       test_case_id: tc,
                                                       status: "triggered"
                                                     } ->
        assert id == automation.id
        assert tc in [tc1, tc2]
        :ok
      end)

      expect(Automations, :establish_alert_baseline, fn ^automation ->
        {:ok, automation}
      end)

      assert :ok = run(automation.id)
    end

    test "subsequent evaluations after the baseline fire on transitions only" do
      automation = AutomationsFixtures.automation_alert_fixture()
      newcomer = Ecto.UUID.generate()
      already = Ecto.UUID.generate()

      expect(FlakyTestsMonitor, :evaluate, fn _automation ->
        %{triggered: [already, newcomer], all: [already, newcomer]}
      end)

      expect(Automations, :list_active_alert_events, fn _id ->
        [%{test_case_id: already, triggered_at: NaiveDateTime.utc_now()}]
      end)

      expected_entity = %{type: :test_case, id: newcomer}

      expect(ActionExecutor, :execute_actions, fn _actions, ^automation, ^expected_entity -> :ok end)

      expect(Automations, :create_alert_event, fn %{
                                                    alert_id: id,
                                                    test_case_id: ^newcomer,
                                                    status: "triggered"
                                                  } ->
        assert id == automation.id
        :ok
      end)

      reject(&Automations.update_alert/2)

      assert :ok = run(automation.id)
    end
  end

  describe "default-branch validation gate" do
    test "skips trigger actions for a test case with no successful default-branch run" do
      automation =
        AutomationsFixtures.automation_alert_fixture(trigger_actions: [%{"type" => "change_state", "state" => "muted"}])

      new_test_id = Ecto.UUID.generate()

      expect(FlakyTestsMonitor, :evaluate, fn _automation ->
        %{triggered: [new_test_id], all: [new_test_id]}
      end)

      expect(Tests, :test_case_ids_with_successful_default_branch_run, fn _project_id, [^new_test_id], _branch ->
        []
      end)

      expect(Automations, :list_active_alert_events, fn _id -> [] end)

      reject(&ActionExecutor.execute_actions/3)
      reject(&Automations.create_alert_event/1)

      assert :ok = run(automation.id)
    end

    test "fires only for validated test cases when the triggered set mixes new and validated tests" do
      automation =
        AutomationsFixtures.automation_alert_fixture(trigger_actions: [%{"type" => "change_state", "state" => "muted"}])

      validated_id = Ecto.UUID.generate()
      new_test_id = Ecto.UUID.generate()

      expect(FlakyTestsMonitor, :evaluate, fn _automation ->
        %{triggered: [validated_id, new_test_id], all: [validated_id, new_test_id]}
      end)

      expect(Tests, :test_case_ids_with_successful_default_branch_run, fn _project_id, ids, _branch ->
        assert validated_id in ids
        assert new_test_id in ids
        [validated_id]
      end)

      expect(Automations, :list_active_alert_events, fn _id -> [] end)

      expected_entity = %{type: :test_case, id: validated_id}
      expect(ActionExecutor, :execute_actions, fn _actions, ^automation, ^expected_entity -> :ok end)

      expect(Automations, :create_alert_event, fn %{test_case_id: ^validated_id, status: "triggered"} -> :ok end)

      assert :ok = run(automation.id)
    end

    test "baseline establishment excludes test cases not validated on the default branch" do
      automation = AutomationsFixtures.automation_alert_fixture(baseline_established_at: nil)

      validated_id = Ecto.UUID.generate()
      new_test_id = Ecto.UUID.generate()

      expect(FlakyTestsMonitor, :evaluate, fn _automation ->
        %{triggered: [validated_id, new_test_id], all: [validated_id, new_test_id]}
      end)

      expect(Tests, :test_case_ids_with_successful_default_branch_run, fn _project_id, _ids, _branch ->
        [validated_id]
      end)

      expect(Automations, :create_alert_event, fn %{test_case_id: ^validated_id, status: "triggered"} -> :ok end)

      expect(Automations, :establish_alert_baseline, fn ^automation ->
        {:ok, automation}
      end)

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = run(automation.id)
    end
  end

  test "dispatches lt-comparison alerts to the metric's evaluator" do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 1, "window_type" => "last_days", "window" => "30d", "comparison" => "lt"},
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
