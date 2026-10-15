defmodule Tuist.Automations.Workers.BuildAlertEvaluationWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :build_automation_evaluations,
    max_attempts: 3,
    unique: [fields: [:worker, :args], keys: [:alert_id], period: :infinity, states: :incomplete]

  alias Tuist.Automations
  alias Tuist.Automations.Builds

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => alert_id}}) do
    case Automations.get_alert(alert_id) do
      {:ok, %{enabled: true} = alert} -> if Builds.monitor?(alert), do: Builds.evaluate(alert), else: :ok
      _ -> :ok
    end
  end

  @impl Oban.Worker
  def backoff(_job), do: 30

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 4)
end
