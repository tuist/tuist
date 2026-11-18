defmodule Tuist.Runners.Workers.RecordWorkflowRunWorker do
  @moduledoc """
  Stores a `workflow_run` webhook's run (`Tuist.Runners.WorkflowRuns.record/3`)
  off the request path, like `DispatchWorker` does for `workflow_job`.
  """
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 3,
    unique: [period: 2 * 60 * 60, keys: [:delivery_guid]]

  alias Tuist.Runners.WorkflowRuns

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run" => run, "installation_id" => installation_id} = args}) do
    case WorkflowRuns.record(run, installation_id, args["account_id"]) do
      {:ok, _run} -> :ok
      {:ignored, _reason} -> :ok
      {:error, _reason} = error -> error
    end
  end
end
