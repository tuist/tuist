defmodule Tuist.Automations.Workers.AlertEvaluationBatchWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Automations.Workers.AlertEvaluationBatchWorker
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Automations.Workers.SlackNotificationWorker
  alias Tuist.IngestRepo
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    stub(Tests, :test_case_ids_with_successful_default_branch_run, fn _, ids, _ -> ids end)
    :ok
  end

  test "a thousand matches become five persisted jobs without running actions" do
    alert = AutomationsFixtures.automation_alert_fixture()
    ids = Enum.sort(Enum.map(1..1000, fn _ -> Ecto.UUID.generate() end))
    expect(FlakyTestsMonitor, :evaluate, fn _ -> %{triggered: ids} end)
    reject(&ActionExecutor.execute_actions/3)
    assert :ok = AlertEvaluationWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id}})
    jobs = all_enqueued(worker: AlertEvaluationBatchWorker)
    assert length(jobs) == 5
    assert Enum.all?(jobs, &(length(&1.args["test_case_ids"]) == 200))
    assert Enum.sort(Enum.flat_map(jobs, & &1.args["test_case_ids"])) == ids
    assert :ok = AlertEvaluationBatchWorker.enqueue(alert, ids, nil, [])
    assert length(all_enqueued(worker: AlertEvaluationBatchWorker)) == 5
  end

  test "includes recovery candidates without leaking active tests from other ranges" do
    alert = AutomationsFixtures.automation_alert_fixture()
    [triggered, recovering, outside] = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)
    active = Enum.map([recovering, outside], &%{test_case_id: &1})
    AlertEvaluationBatchWorker.enqueue(alert, [triggered], [triggered, recovering], active)
    assert [job] = all_enqueued(worker: AlertEvaluationBatchWorker)
    assert Enum.sort(job.args["test_case_ids"]) == Enum.sort([triggered, recovering])
  end

  test "already active matches need no batch and executing batches allow a successor" do
    alert = AutomationsFixtures.automation_alert_fixture()
    id = Ecto.UUID.generate()
    AlertEvaluationBatchWorker.enqueue(alert, [id], nil, [%{test_case_id: id}])
    assert all_enqueued(worker: AlertEvaluationBatchWorker) == []
    AlertEvaluationBatchWorker.enqueue(alert, [id], nil, [])
    [pending] = all_enqueued(worker: AlertEvaluationBatchWorker)
    Repo.update!(Ecto.Changeset.change(pending, state: "executing"))
    AlertEvaluationBatchWorker.enqueue(alert, [id], nil, [])
    assert [successor] = all_enqueued(worker: AlertEvaluationBatchWorker)
    refute successor.id == pending.id
  end

  test "a Slack outage leaves applied state and its ledger complete" do
    {:ok, encrypted} = Slack.encrypt_webhook_url("https://hooks.slack.com/services/test")

    alert =
      AutomationsFixtures.automation_alert_fixture(
        trigger_actions: [
          %{"type" => "change_state", "state" => "skipped"},
          %{
            "type" => "send_slack",
            "channel" => "C123",
            "message" => "Matched {{test_case.name}}",
            "webhook_url_encrypted" => encrypted
          }
        ]
      )

    test_case = [project_id: alert.project_id] |> RunsFixtures.test_case_fixture() |> IngestRepo.insert!()
    stub(FlakyTestsMonitor, :evaluate, fn _, ids -> %{triggered: ids} end)
    assert :ok = AlertEvaluationBatchWorker.perform(job(alert, [test_case.id]))
    assert {:ok, %{state: "skipped"}} = Tests.get_test_case_by_id(test_case.id)
    assert length(Automations.list_active_alert_events(alert)) == 1
    assert [notification] = all_enqueued(worker: SlackNotificationWorker)
    expect(Client, :deliver_once, fn _, _ -> {:error, :slack_unavailable} end)
    assert {:error, :slack_unavailable} = SlackNotificationWorker.perform(notification)
    reject(&ActionExecutor.execute_actions/3)
    assert :ok = AlertEvaluationBatchWorker.perform(job(alert, [test_case.id]))
    assert length(all_enqueued(worker: SlackNotificationWorker)) == 1
    assert length(Automations.list_active_alert_events(alert)) == 1
  end

  test "a queued match that has cleared does not run stale trigger actions" do
    alert = AutomationsFixtures.automation_alert_fixture()
    id = Ecto.UUID.generate()
    expect(FlakyTestsMonitor, :evaluate, fn _, [^id] -> %{triggered: []} end)
    reject(&ActionExecutor.execute_actions/3)
    assert :ok = AlertEvaluationBatchWorker.perform(job(alert, [id]))
    assert Automations.list_active_alert_events(alert) == []
  end

  test "a retry skips completed transitions and retries failed actions" do
    alert = AutomationsFixtures.automation_alert_fixture()
    [first, second] = Enum.map(1..2, fn _ -> Ecto.UUID.generate() end)
    stub(FlakyTestsMonitor, :evaluate, fn _, ids -> %{triggered: ids} end)
    expect(ActionExecutor, :execute_actions, fn _, _, %{id: ^first} -> :ok end)
    expect(ActionExecutor, :execute_actions, fn _, _, %{id: ^second} -> {:error, :queue_unavailable} end)
    assert {:error, :actions_failed} = AlertEvaluationBatchWorker.perform(job(alert, [first, second]))
    assert [%{test_case_id: ^first}] = Automations.list_active_alert_events(alert)
    expect(ActionExecutor, :execute_actions, fn _, _, %{id: ^second} -> :ok end)
    assert :ok = AlertEvaluationBatchWorker.perform(job(alert, [first, second]))
    assert length(Automations.list_active_alert_events(alert)) == 2
  end

  test "disabled alerts and superseded baseline generations are skipped" do
    alert = AutomationsFixtures.automation_alert_fixture()
    job = job(alert, [Ecto.UUID.generate()])
    reject(&FlakyTestsMonitor.evaluate/2)
    {:ok, _} = Automations.update_alert(alert, %{enabled: false})
    assert :ok = AlertEvaluationBatchWorker.perform(job)

    {:ok, _} =
      Automations.update_alert(alert, %{
        enabled: true,
        trigger_config: %{"threshold" => 20, "window_type" => "last_days", "window" => "30d"}
      })

    assert :ok = AlertEvaluationBatchWorker.perform(job)
  end

  test "failed dispatch does not advance the scoped evaluation watermark" do
    alert =
      AutomationsFixtures.automation_alert_fixture(
        trigger_config: %{"threshold" => 10, "window_type" => "rolling", "rolling_window_size" => 100}
      )

    before = DateTime.add(DateTime.utc_now(:second), -120, :second)
    {:ok, alert} = Automations.update_alert_scoped_evaluation_cursor(alert, before)

    stub(Automations, :recent_test_case_run_changes_for_alert, fn _ ->
      %{test_case_ids: [Ecto.UUID.generate()], cursor: DateTime.utc_now(:second), more?: false}
    end)

    stub(FlakyTestsMonitor, :evaluate, fn _, ids -> %{triggered: ids} end)
    stub(AlertEvaluationBatchWorker, :enqueue, fn _, _, _, _ -> raise "enqueue failed" end)

    assert_raise RuntimeError, "enqueue failed", fn ->
      AlertEvaluationWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id, "evaluate_recent_test_case_runs" => true}})
    end

    assert Repo.reload!(alert).last_scoped_evaluation_inserted_at == before
  end

  defp job(alert, ids),
    do: %Oban.Job{
      args: %{"alert_id" => alert.id, "baseline_generation" => alert.baseline_generation, "test_case_ids" => ids}
    }
end
