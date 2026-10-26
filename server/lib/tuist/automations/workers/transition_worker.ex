defmodule Tuist.Automations.Workers.TransitionWorker do
  @moduledoc false
  use Oban.Worker, queue: :automation_transitions, max_attempts: 10

  alias Tuist.Automations.Execution.Transitions

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 2)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transition_id" => id}} = job) do
    Transitions.apply(id)
  rescue
    error ->
      Transitions.failure(id, job.attempt >= job.max_attempts)
      reraise error, __STACKTRACE__
  end
end
