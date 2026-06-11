defmodule Tuist.Automations.Workers.AutomationSchedulerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Automations.Workers.AutomationScheduler
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  test "enqueues evaluation jobs for enabled alerts" do
    alert = AutomationsFixtures.automation_alert_fixture()

    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert_enqueued(worker: AlertEvaluationWorker, args: %{alert_id: alert.id})
  end

  test "does not schedule established rolling scoped-monitor alerts" do
    for monitor_type <- ["flakiness_rate", "flaky_run_count", "reliability_rate"] do
      AutomationsFixtures.automation_alert_fixture(
        monitor_type: monitor_type,
        trigger_config: %{"threshold" => 1, "window_type" => "rolling", "rolling_window_size" => 100}
      )
    end

    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert [] = all_enqueued(worker: AlertEvaluationWorker)
  end

  test "schedules rolling alerts until their baseline is established" do
    alert =
      AutomationsFixtures.automation_alert_fixture(
        baseline_established_at: nil,
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 1, "window_type" => "rolling", "rolling_window_size" => 100}
      )

    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert_enqueued(worker: AlertEvaluationWorker, args: %{alert_id: alert.id})
  end

  test "does not schedule event-driven test_updated alerts" do
    AutomationsFixtures.automation_alert_fixture(
      monitor_type: "test_updated",
      trigger_config: %{"events" => ["marked_flaky"]}
    )

    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert [] = all_enqueued(worker: AlertEvaluationWorker)
  end

  test "does not enqueue overlapping scheduler jobs" do
    assert {:ok, %Oban.Job{conflict?: false}} =
             %{}
             |> AutomationScheduler.new()
             |> Oban.insert()

    assert {:ok, %Oban.Job{conflict?: true}} =
             %{}
             |> AutomationScheduler.new()
             |> Oban.insert()

    assert [_job] = all_enqueued(worker: AutomationScheduler)
  end
end
