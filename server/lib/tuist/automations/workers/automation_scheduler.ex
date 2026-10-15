defmodule Tuist.Automations.Workers.AutomationScheduler do
  @moduledoc false
  use Oban.Worker,
    max_attempts: 1,
    queue: :default,
    unique: [fields: [:worker], period: :infinity, states: :incomplete]

  import Ecto.Query

  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Builds
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Automations.Workers.BuildAlertEvaluationWorker
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    alerts = Repo.all(from(a in Alert, where: a.enabled == true))

    Enum.each(alerts, fn alert ->
      if scheduled_alert?(alert) do
        # The scheduler itself runs on a fixed cron (~1 minute). Without
        # including `:completed` in the uniqueness state set, a fast-running
        # evaluation job would move to :completed within seconds, and the next
        # scheduler tick would queue another one — collapsing the effective
        # cadence to the scheduler's interval. Checking `:completed` + the
        # per-alert `period` guarantees we wait at least `cadence` seconds
        # before re-scheduling, regardless of how quickly the previous run
        # finished.
        worker = if Builds.monitor?(alert), do: BuildAlertEvaluationWorker, else: AlertEvaluationWorker

        {:ok, _job} =
          %{alert_id: alert.id}
          |> worker.new(
            unique: [
              keys: [:alert_id],
              period: Alert.cadence_seconds(alert.cadence),
              states: [:available, :scheduled, :executing, :completed]
            ]
          )
          |> Oban.insert()
      end
    end)

    :ok
  end

  defp scheduled_alert?(alert) do
    cond do
      Alert.event_driven?(alert) -> false
      Alert.scoped_evaluation?(alert) -> false
      true -> true
    end
  end
end
