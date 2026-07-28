defmodule Tuist.Automations.Workers.AutomationSchedulerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Automations.Workers.AutomationScheduler
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "enqueues evaluation jobs for enabled alerts" do
    alert = AutomationsFixtures.automation_alert_fixture()

    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert_enqueued(worker: AlertEvaluationWorker, args: %{alert_id: alert.id})
  end

  test "does not schedule established rolling scoped-monitor alerts" do
    for monitor_type <- ["flakiness_rate", "flaky_run_count", "reliability_rate"] do
      AutomationsFixtures.automation_alert_fixture(
        monitor_type: monitor_type,
        trigger_config: %{"threshold" => 1, "window_type" => "rolling", "rolling_window_size" => 75}
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
        trigger_config: %{"threshold" => 1, "window_type" => "rolling", "rolling_window_size" => 75}
      )

    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert_enqueued(worker: AlertEvaluationWorker, args: %{alert_id: alert.id})
  end

  test "calendar-window alerts are owned only by the scheduler" do
    project = ProjectsFixtures.project_fixture()
    alert = AutomationsFixtures.automation_alert_fixture(project: project, monitor_type: "flakiness_rate")

    assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [Ecto.UUID.generate()])
    assert :ok = AutomationScheduler.perform(%Oban.Job{args: %{}})

    assert [%{args: %{"alert_id" => alert_id}}] = all_enqueued(worker: AlertEvaluationWorker)
    assert alert_id == alert.id
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
