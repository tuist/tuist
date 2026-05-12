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
