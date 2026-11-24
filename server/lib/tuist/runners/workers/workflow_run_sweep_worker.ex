defmodule Tuist.Runners.Workers.WorkflowRunSweepWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 300]

  alias Tuist.Runners.WorkflowRuns

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _count} <- WorkflowRuns.sweep(), do: :ok
  end
end
