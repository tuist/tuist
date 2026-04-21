defmodule Tuist.Automations.Workers.AutomationScheduler do
  @moduledoc false
  use Oban.Worker, max_attempts: 1, queue: :default

  import Ecto.Query

  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    alerts = Repo.all(from(a in Alert, where: a.enabled == true))

    Enum.each(alerts, fn alert ->
      # The scheduler itself runs on a fixed cron (~1 minute). Without
      # including `:completed` in the uniqueness state set, a fast-running
      # evaluation job would move to :completed within seconds, and the next
      # scheduler tick would queue another one — collapsing the effective
      # cadence to the scheduler's interval. Checking `:completed` + the
      # per-alert `period` guarantees we wait at least `cadence` seconds
      # before re-scheduling, regardless of how quickly the previous run
      # finished.
      {:ok, _job} =
        %{alert_id: alert.id}
        |> AlertEvaluationWorker.new(
          unique: [
            keys: [:alert_id],
            period: cadence_seconds(alert.cadence),
            states: [:available, :scheduled, :executing, :completed]
          ]
        )
        |> Oban.insert()
    end)

    :ok
  end

  defp cadence_seconds(cadence) when is_binary(cadence) do
    case Integer.parse(cadence) do
      {value, "m"} -> value * 60
      {value, "h"} -> value * 3600
      {value, "s"} -> value
      _ -> 300
    end
  end

  defp cadence_seconds(_), do: 300
end
