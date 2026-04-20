defmodule Tuist.Automations.Workers.AutomationScheduler do
  @moduledoc false
  use Oban.Worker, max_attempts: 1, queue: :default

  import Ecto.Query

  alias Tuist.Automations.AlertRule
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    alert_rules = Repo.all(from(a in AlertRule, where: a.enabled == true))

    Enum.each(alert_rules, fn alert_rule ->
      {:ok, _job} =
        %{alert_rule_id: alert_rule.id}
        |> AlertEvaluationWorker.new(
          unique: [
            keys: [:alert_rule_id],
            period: cadence_seconds(alert_rule.cadence),
            states: [:available, :scheduled, :executing]
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
