defmodule Tuist.Automations.Workers.AutomationScheduler do
  @moduledoc false
  use Oban.Worker, max_attempts: 1, queue: :default

  import Ecto.Query

  alias Tuist.Automations.Automation
  alias Tuist.Automations.Workers.AutomationEvaluationWorker
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    automations = Repo.all(from(a in Automation, where: a.enabled == true))

    Enum.each(automations, fn automation ->
      %{automation_id: automation.id}
      |> AutomationEvaluationWorker.new(unique: [period: cadence_seconds(automation.cadence)])
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
