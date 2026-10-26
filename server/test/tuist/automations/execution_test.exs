defmodule Tuist.Automations.ExecutionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Alerts.Event
  alias Tuist.Automations.Execution
  alias Tuist.Automations.Execution.Delivery
  alias Tuist.Automations.Execution.Evaluation
  alias Tuist.Automations.Execution.Operations
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Automations.Execution.Transitions
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Automations.Workers.AutomationDeliveryWorker
  alias Tuist.Automations.Workers.AutomationScheduler
  alias Tuist.Automations.Workers.EvaluationPageWorker
  alias Tuist.Automations.Workers.TransitionFanoutWorker
  alias Tuist.Automations.Workers.TransitionWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    stub(Tests, :test_case_ids_with_successful_default_branch_run, fn _, ids, _ -> ids end)
    stub(FlakyTestsMonitor, :evaluate, fn _, ids -> %{triggered: ids} end)
    :ok
  end

  test "session ownership fails closed on transaction-mode poolers" do
    stub(Environment, :database_pooled?, fn -> true end)

    assert_raise RuntimeError, ~r/require a direct PostgreSQL connection/, fn ->
      Execution.with_lock("test", fn -> flunk("must not run without session ownership") end)
    end
  end

  test "activation refuses an executing project evaluation" do
    alert = AutomationsFixtures.automation_alert_fixture()

    job =
      Oban.insert!(
        AlertEvaluationWorker.new(%{
          project_id: alert.project_id,
          cadence_seconds: 300,
          evaluate_recent_test_case_runs: true
        })
      )

    job = Repo.update!(Ecto.Changeset.change(job, state: "executing"))
    assert {:error, :evaluation_in_progress} = Execution.enable(alert.id)
    refute Repo.reload!(alert).durable_execution
    Repo.update!(Ecto.Changeset.change(job, state: "completed"))
    assert {:ok, %{durable_execution: true}} = Execution.enable(alert.id)
  end

  test "the scheduler and entry worker route durable rolling alerts to persisted pages" do
    alert = alert(trigger_config: %{"threshold" => 10, "window_type" => "rolling", "rolling_window_size" => 100})
    reject(&FlakyTestsMonitor.evaluate/2)
    assert :ok = AutomationScheduler.perform(%Oban.Job{})
    assert [job] = all_enqueued(worker: AlertEvaluationWorker)
    assert job.args == %{"alert_id" => alert.id, "evaluate_recent_test_case_runs" => true}
    assert :ok = AlertEvaluationWorker.perform(job)
    assert Repo.one!(Evaluation).alert_id == alert.id
    assert length(all_enqueued(worker: EvaluationPageWorker)) == 1
  end

  test "an alert edit cancels an unsent notification without repeating state changes" do
    {alert, _, transition} = transition()
    Transitions.apply(transition.id)
    delivery = Repo.one!(Delivery)
    Automations.update_alert(alert, %{enabled: false})
    reject(&SendSlackAction.deliver_once/3)
    assert :ok = AutomationDeliveryWorker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})
    assert Repo.reload!(delivery).state == "cancelled"
    assert Repo.reload!(transition).phase == "applied"
  end

  test "a thousand transitions are persisted in bounded pages without running actions" do
    alert = alert()
    ids = Enum.sort(Enum.map(1..1000, fn _ -> Ecto.UUID.generate() end))
    reject(&SendSlackAction.execute/3)
    assert :ok = Execution.schedule(alert, %{"test_case_ids" => ids})
    run = Repo.one!(Evaluation)
    assert :ok = Execution.evaluate_page(run.id)
    assert Repo.aggregate(Transition, :count) == 200
    assert length(all_enqueued(worker: TransitionWorker)) == 200
    assert length(all_enqueued(worker: EvaluationPageWorker)) == 2
    Enum.each(1..5, fn _ -> assert :ok = Execution.evaluate_page(run.id) end)
    assert Repo.aggregate(Transition, :count) == 1000
    assert Repo.reload!(run).state == "completed"
    assert :ok = Execution.evaluate_page(run.id)
    assert Repo.aggregate(Transition, :count) == 1000
    assert :ok = Execution.schedule(alert, %{"test_case_ids" => ids})
    next = Repo.one!(from(r in Evaluation, where: r.state == "running"))
    Enum.each(1..6, fn _ -> Execution.evaluate_page(next.id) end)
    assert Repo.aggregate(Transition, :count) == 1000
  end

  test "checkpoint and jobs roll back together when a page cannot persist" do
    alert = alert()
    ids = [Ecto.UUID.generate()]
    Execution.schedule(alert, %{"test_case_ids" => ids})
    run = Repo.one!(Evaluation)

    assert {:error, :simulated_crash} =
             Repo.transaction(fn ->
               Execution.evaluate_page(run.id)
               assert Repo.aggregate(Transition, :count) == 1
               Repo.rollback(:simulated_crash)
             end)

    assert Repo.reload!(run).cursor == nil
    assert Repo.aggregate(Transition, :count) == 0
    assert all_enqueued(worker: TransitionWorker) == []
    Execution.evaluate_page(run.id)
    assert Repo.aggregate(Transition, :count) == 1
  end

  test "imports active legacy history without replaying trigger actions" do
    alert = alert()
    id = Ecto.UUID.generate()
    at = ~N[2026-01-01 00:00:00.000000]
    Automations.create_alert_event(%{alert_id: alert.id, test_case_id: id, status: "triggered", triggered_at: at})
    evaluate(alert, [id])
    assert Repo.aggregate(Transition, :count) == 0
    assert Repo.one!(TestState).status == "triggered"
  end

  test "applies a transition once and records notification work separately" do
    {alert, test_case, transition} = transition()
    reject(&SendSlackAction.execute/3)
    assert :ok = Transitions.apply(transition.id)
    assert :ok = Transitions.apply(transition.id)
    assert Repo.reload!(transition).phase == "applied"
    assert Repo.one!(TestState).status == "triggered"
    assert Repo.one!(Delivery).state == "pending"
    assert length(all_enqueued(worker: AutomationDeliveryWorker)) == 1
    assert length(all_enqueued(worker: TransitionFanoutWorker)) == 1
    assert Tests.get_test_case_states(alert.project_id, [test_case.id])[test_case.id].state == "skipped"
  end

  test "replaying a prepared write preserves its timestamp and a newer manual edit" do
    {alert, test_case, transition} = transition()
    test_pid = self()
    # Fail after the state write but before the alert history write and PG commit.
    stub(IngestRepo, :insert_all, fn
      Event, _, _ -> raise "crash after state write"
      schema, rows, opts -> Mimic.call_original(IngestRepo, :insert_all, [schema, rows, opts])
    end)

    assert_raise RuntimeError, "crash after state write", fn -> Transitions.apply(transition.id) end
    prepared = Repo.reload!(transition)
    assert prepared.phase == "prepared"
    assert Repo.aggregate(Delivery, :count) == 0
    {:ok, _} = Tests.update_test_case(test_case.id, %{state: "muted"})

    stub(IngestRepo, :insert_all, fn schema, rows, opts ->
      if schema == Event, do: send(test_pid, {:history_write, rows})
      Mimic.call_original(IngestRepo, :insert_all, [schema, rows, opts])
    end)

    assert :ok = Transitions.apply(transition.id)
    assert Repo.reload!(transition).occurred_at == prepared.occurred_at
    assert Tests.get_test_case_states(alert.project_id, [test_case.id])[test_case.id].state == "muted"
    assert Repo.aggregate(Delivery, :count) == 1
    assert_receive {:history_write, [%{id: id}]}
    assert id == transition.id
  end

  test "trigger recovery and retrigger allocate distinct ordered transitions" do
    {alert, test_case, first} = transition()
    Transitions.apply(first.id)
    stub(FlakyTestsMonitor, :evaluate, fn _, _ -> %{triggered: []} end)
    evaluate(alert, [test_case.id])
    second = Repo.one!(from(t in Transition, where: t.sequence == 2))
    assert second.status == "recovered"
    Transitions.apply(second.id)
    stub(FlakyTestsMonitor, :evaluate, fn _, ids -> %{triggered: ids} end)
    evaluate(alert, [test_case.id])
    third = Repo.one!(from(t in Transition, where: t.sequence == 3))
    assert third.status == "triggered"
    Transitions.apply(third.id)
    assert Repo.one!(TestState).status == "triggered"
  end

  test "edits cancel pending execution while prepared payloads remain resumable" do
    {alert, _, transition} = transition()
    {:ok, _} = Automations.update_alert(alert, %{enabled: false})
    reject(&Tests.prepare_automation_update/3)
    assert :ok = Transitions.apply(transition.id)
    assert Repo.reload!(transition).phase == "cancelled"
    assert Repo.one!(TestState).pending_transition_id == nil
    assert Repo.one!(TestState).status == "recovered"
  end

  test "notification retries and throttling do not reapply the transition" do
    {_, _, transition} = transition()
    Transitions.apply(transition.id)
    delivery = Repo.one!(Delivery)
    expect(SendSlackAction, :deliver_once, fn _, _, _ -> {:snooze, 30} end)
    job = %Oban.Job{args: %{"delivery_id" => delivery.id}, attempt: 1, max_attempts: 12}
    assert {:snooze, 30} = AutomationDeliveryWorker.perform(job)
    assert Repo.reload!(delivery).attempts == 1
    reject(&SendSlackAction.deliver_once/3)
    assert {:snooze, seconds} = AutomationDeliveryWorker.perform(job)
    assert seconds > 0 and seconds <= 30
    assert Repo.reload!(delivery).attempts == 1
    assert Repo.reload!(transition).phase == "applied"
  end

  test "permanent and exhausted delivery failures stay inspectable" do
    {_, _, transition} = transition()
    Transitions.apply(transition.id)
    delivery = Repo.one!(Delivery)
    expect(SendSlackAction, :deliver_once, fn _, _, _ -> {:error, :slack_unavailable} end)

    assert {:error, :slack_unavailable} =
             AutomationDeliveryWorker.perform(%Oban.Job{
               args: %{"delivery_id" => delivery.id},
               attempt: 12,
               max_attempts: 12
             })

    assert Repo.reload!(delivery).state == "failed"
    assert Repo.reload!(delivery).error == "slack_unavailable"
    assert Repo.reload!(transition).phase == "applied"
  end

  test "fanout is checkpointed and cannot enqueue downstream work twice" do
    {_, _, transition} = transition()
    Transitions.apply(transition.id)
    job = %Oban.Job{args: %{"transition_id" => transition.id}}
    assert :ok = TransitionFanoutWorker.perform(job)
    jobs = Repo.aggregate(Oban.Job, :count)
    assert :ok = TransitionFanoutWorker.perform(job)
    assert Repo.aggregate(Oban.Job, :count) == jobs
    assert Repo.reload!(transition).fanout_done
  end

  test "configuration changes invalidate an unfinished evaluation" do
    alert = alert()
    Execution.schedule(alert, %{"test_case_ids" => [Ecto.UUID.generate()]})
    run = Repo.one!(Evaluation)
    {:ok, _} = Automations.update_alert(alert, %{trigger_actions: [%{"type" => "change_state", "state" => "muted"}]})
    Execution.evaluate_page(run.id)
    assert Repo.reload!(run).state == "cancelled"
    assert Repo.aggregate(Transition, :count) == 0
  end

  test "fanout reserves ordered event actions once and enforces the depth bound" do
    project = ProjectsFixtures.project_fixture()

    alert =
      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "test_updated",
        trigger_config: %{"events" => ["state_changed_to_skipped"]}
      )

    test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
    source = Ecto.UUID.generate()

    Repo.transaction(fn ->
      Automations.enqueue_test_case_event(:skipped, test_case, source, 0)
      Automations.enqueue_test_case_event(:skipped, test_case, source, 0)
      Automations.enqueue_test_case_event(:skipped, test_case, Ecto.UUID.generate(), 0)
      Automations.enqueue_test_case_event(:skipped, test_case, Ecto.UUID.generate(), 10)
    end)

    assert Repo.one!(TestState).alert_id == alert.id
    assert [first, second] = Repo.all(from(t in Transition, order_by: t.sequence))
    assert first.source_id == source
    assert first.depth == 1
    assert second.sequence == first.sequence + 1
    assert Repo.one!(TestState).pending_transition_id == first.id
    assert {:snooze, 1} = Transitions.apply(second.id)
  end

  test "failed fanout rolls back descendants and retries from the same source" do
    {alert, test_case, transition} = transition()

    subscriber =
      AutomationsFixtures.automation_alert_fixture(
        project_id: alert.project_id,
        monitor_type: "test_updated",
        trigger_config: %{"events" => ["state_changed_to_skipped"]}
      )

    Transitions.apply(transition.id)

    stub(Automations, :enqueue_test_case_event, fn type, snapshot, source, depth ->
      Mimic.call_original(Automations, :enqueue_test_case_event, [type, snapshot, source, depth])
      raise "crash after descendant reservation"
    end)

    job = %Oban.Job{args: %{"transition_id" => transition.id}}
    assert_raise RuntimeError, "crash after descendant reservation", fn -> TransitionFanoutWorker.perform(job) end
    refute Repo.reload!(transition).fanout_done
    assert Repo.aggregate(Transition, :count) == 1

    stub(Automations, :enqueue_test_case_event, fn type, snapshot, source, depth ->
      Mimic.call_original(Automations, :enqueue_test_case_event, [type, snapshot, source, depth])
    end)

    {:ok, _} = Tests.update_test_case(test_case.id, %{state: "muted"})
    Phoenix.PubSub.subscribe(Tuist.PubSub, Tests.test_case_topic(test_case.id))
    assert :ok = TransitionFanoutWorker.perform(job)
    assert_receive {:test_case_updated, %{state: "muted"}}
    assert Repo.one!(from(s in TestState, where: s.alert_id == ^subscriber.id))
    assert Repo.aggregate(Transition, :count) == 2
    assert :ok = TransitionFanoutWorker.perform(job)
    assert Repo.aggregate(Transition, :count) == 2
  end

  test "disabling and re-enabling an alert cannot resurrect old work" do
    {alert, _, transition} = transition()
    {:ok, disabled} = Automations.update_alert(alert, %{enabled: false})
    {:ok, enabled} = Automations.update_alert(disabled, %{enabled: true})
    assert enabled.execution_revision == alert.execution_revision + 2
    assert Execution.revision(enabled) != transition.revision
    assert :ok = Transitions.apply(transition.id)
    assert Repo.reload!(transition).phase == "cancelled"
  end

  test "a silent baseline is paged durably without applying existing-match actions" do
    alert = alert(baseline_established_at: nil)
    test_case = [project_id: alert.project_id] |> RunsFixtures.test_case_fixture() |> IngestRepo.insert!()
    page = Map.take(test_case, [:id, :name, :module_name, :suite_name])
    expect(Automations, :list_alert_baseline_test_case_page, fn _, nil, 200 -> [page] end)

    expect(Automations, :list_alert_baseline_test_case_page, fn _, cursor, 200 ->
      assert cursor["id"] == test_case.id
      []
    end)

    Execution.schedule(alert)
    run = Repo.one!(Evaluation)
    Execution.evaluate_page(run.id)
    assert Repo.reload!(alert).baseline_established_at == nil
    assert Repo.one!(Transition).actions == []
    Execution.evaluate_page(run.id)
    assert Repo.reload!(alert).baseline_established_at
    Transitions.apply(Repo.one!(Transition).id)
    assert Repo.one!(TestState).status == "triggered"
    assert Repo.aggregate(Delivery, :count) == 0
    assert Tests.get_test_case_states(alert.project_id, [test_case.id])[test_case.id].state == "enabled"
  end

  test "an opted-in baseline reapplies actions even for an already active test" do
    alert =
      alert(
        baseline_established_at: nil,
        trigger_config: %{
          "threshold" => 10,
          "window_type" => "last_days",
          "window" => "30d",
          "apply_actions_to_existing_matches" => true
        }
      )

    test_case = [project_id: alert.project_id] |> RunsFixtures.test_case_fixture() |> IngestRepo.insert!()

    Automations.create_alert_event(%{
      alert_id: alert.id,
      test_case_id: test_case.id,
      status: "triggered",
      triggered_at: NaiveDateTime.utc_now()
    })

    page = Map.take(test_case, [:id, :name, :module_name, :suite_name])
    stub(Automations, :list_alert_baseline_test_case_page, fn _, cursor, 200 -> if cursor, do: [], else: [page] end)
    Execution.schedule(alert)
    run = Repo.one!(Evaluation)
    Execution.evaluate_page(run.id)
    Execution.evaluate_page(run.id)
    assert Repo.one!(Transition).actions == alert.trigger_actions
    assert Repo.reload!(alert).trigger_config["apply_actions_to_existing_matches"] == nil
    Transitions.apply(Repo.one!(Transition).id)
    assert Repo.aggregate(Delivery, :count) == 1
  end

  test "a scoped evaluation advances its watermark only after committing its pages" do
    alert = alert(trigger_config: %{"threshold" => 10, "window_type" => "rolling", "rolling_window_size" => 100})
    before = DateTime.add(DateTime.utc_now(:second), -60, :second)
    {:ok, alert} = Automations.update_alert_scoped_evaluation_cursor(alert, before)
    id = Ecto.UUID.generate()
    stub(Automations, :list_active_alert_events, fn _, _ -> [] end)

    expect(ClickHouseRepo, :all, fn query ->
      assert query.limit.expr == 200
      [id]
    end)

    expect(ClickHouseRepo, :all, fn _ -> [] end)
    Execution.schedule(alert, %{"evaluate_recent_test_case_runs" => true})
    run = Repo.one!(Evaluation)
    Execution.evaluate_page(run.id)
    assert Repo.reload!(alert).last_scoped_evaluation_inserted_at == before
    assert Repo.aggregate(Transition, :count) == 1
    Execution.evaluate_page(run.id)
    assert DateTime.after?(Repo.reload!(alert).last_scoped_evaluation_inserted_at, before)
  end

  test "recovery rearms without undoing a manual edit after evaluation" do
    alert =
      alert(
        recovery_enabled: true,
        recovery_config: %{"window_type" => "last_days", "window" => "1d", "states" => ["skipped"]},
        recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
      )

    test_case = [project_id: alert.project_id] |> RunsFixtures.test_case_fixture() |> IngestRepo.insert!()
    evaluate(alert, [test_case.id])
    Transitions.apply(Repo.one!(Transition).id)

    TestState
    |> Repo.one!()
    |> Ecto.Changeset.change(triggered_at: DateTime.add(DateTime.utc_now(), -2, :day))
    |> Repo.update!()

    stub(FlakyTestsMonitor, :evaluate, fn _, _ -> %{triggered: []} end)
    evaluate(alert, [test_case.id])
    recovery = Repo.one!(from(t in Transition, where: t.status == "recovered"))
    {:ok, _} = Tests.update_test_case(test_case.id, %{state: "muted"})
    assert :ok = Transitions.apply(recovery.id)
    assert Repo.one!(TestState).status == "recovered"
    assert Tests.get_test_case_states(alert.project_id, [test_case.id])[test_case.id].state == "muted"
  end

  test "retention preserves unresolved deliveries and compact applied state" do
    {alert, _, transition} = transition()
    Transitions.apply(transition.id)

    transition
    |> Repo.reload!()
    |> Ecto.Changeset.change(fanout_done: true, updated_at: DateTime.add(DateTime.utc_now(:second), -31, :day))
    |> Repo.update!()

    delivery = Repo.one!(Delivery)
    Repo.update!(Ecto.Changeset.change(delivery, state: "failed"))
    assert :ok = Operations.prune()
    assert Repo.get(Transition, transition.id)
    assert [%{state: "failed", count: 1}] = Operations.status(alert.id).deliveries
    Repo.update!(Ecto.Changeset.change(delivery, state: "delivered"))
    assert :ok = Operations.prune()
    assert Repo.get(Transition, transition.id) == nil
    assert Repo.aggregate(Delivery, :count) == 0
    assert Repo.one!(TestState).status == "triggered"
  end

  defp alert(opts \\ []) do
    alert =
      [
        trigger_actions: [
          %{"type" => "change_state", "state" => "skipped"},
          %{"type" => "send_slack", "channel" => "C-#{Ecto.UUID.generate()}", "message" => "Test {{test_case.name}}"}
        ]
      ]
      |> Keyword.merge(opts)
      |> AutomationsFixtures.automation_alert_fixture()

    {:ok, alert} = Execution.enable(alert.id)
    alert
  end

  defp evaluate(alert, ids) do
    Execution.schedule(alert, %{"test_case_ids" => ids})
    run = Repo.one!(from(r in Evaluation, where: r.state == "running"))
    Execution.evaluate_page(run.id)
    Execution.evaluate_page(run.id)
  end

  defp transition do
    alert = alert()
    test_case = [project_id: alert.project_id] |> RunsFixtures.test_case_fixture() |> IngestRepo.insert!()
    evaluate(alert, [test_case.id])
    {alert, test_case, Repo.one!(Transition)}
  end
end
