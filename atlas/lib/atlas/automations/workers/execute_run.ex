defmodule Atlas.Automations.Workers.ExecuteRun do
  @moduledoc false

  use Oban.Worker, queue: :automation, max_attempts: 5, tags: ["automation"]

  alias Atlas.Automations.Executor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => id}} = job) do
    case Executor.advance(id, job) do
      {:ok, :busy} -> {:snooze, 2}
      {:ok, _} -> :ok
      {:error, _} -> {:error, :execution_transition_failed}
    end
  end
end
