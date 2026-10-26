defmodule Tuist.Automations.Workers.PruneExecutionWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: :infinity, states: :incomplete]

  alias Tuist.Automations.Execution.Operations

  @impl Oban.Worker
  def perform(_job), do: Operations.prune()
end
