defmodule Tuist.Automations.Workers.EvaluationPageWorker do
  @moduledoc false
  use Oban.Worker, queue: :alert_evaluations, max_attempts: 10

  alias Tuist.Automations.Execution

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 4)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"evaluation_id" => id}}), do: Execution.evaluate_page(id)
end
