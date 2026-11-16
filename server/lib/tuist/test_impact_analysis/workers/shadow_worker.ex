defmodule Tuist.TestImpactAnalysis.Workers.ShadowWorker do
  @moduledoc """
  Decides a selection again from snapshots (`Tuist.TestImpactAnalysis.Shadow`)
  after the runs request recorded it, off the request's path. A run it can't
  decide (no stored diff, no checkpoint at its baseline yet) is left alone.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [keys: [:test_impact_run_id], period: :infinity]

  alias Tuist.Projects
  alias Tuist.TestImpactAnalysis.Shadow
  alias Tuist.TestImpactAnalysis.Storage

  def enqueue(project_id, test_impact_run_id) do
    %{project_id: project_id, test_impact_run_id: test_impact_run_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "test_impact_run_id" => run_id}}) do
    with %{} = project <- Projects.get_project_by_id(project_id),
         {:ok, run} <- Storage.get_run(project_id, run_id) do
      Shadow.decide(project, run)
    end

    :ok
  end
end
