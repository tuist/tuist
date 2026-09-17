defmodule Tuist.Tests.Coverage.Workers.RecomputeTotalsWorker do
  @moduledoc """
  Republishes a project's coverage totals after its excluded paths changed
  (`Tuist.Tests.Coverage.recompute_totals/2`), so the trend, the branches and
  the baselines read the same figures as the runs' own pages. One batch of
  runs per job, each job enqueueing the next; the batch size comes from
  `TUIST_COVERAGE_RECOMPUTE_BATCH_SIZE`. The exclusions are read when each
  batch runs, so a later change is picked up by the batches still to come and
  by the chain it enqueues itself.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :after], states: [:available, :scheduled]]

  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Tests.Coverage

  def enqueue(project_id), do: %{project_id: project_id} |> new() |> Oban.insert()

  @doc """
  The jobs that republish the totals of every project with coverage, for when
  the server's excluded paths changed (`TUIST_COVERAGE_EXCLUDED_PATH_GLOBS`,
  or a release that changes the defaults): a project only recomputes by
  itself when its own globs change.
  """
  def jobs_for_all_projects do
    Enum.map(Coverage.project_ids_with_coverage(), &new(%{project_id: &1}))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id} = args}) do
    if Projects.get_project_by_id(project_id) do
      case Coverage.recompute_totals(project_id,
             after: args["after"],
             batch_size: Environment.coverage_recompute_batch_size()
           ) do
        nil -> :ok
        last -> %{project_id: project_id, after: last} |> new() |> Oban.insert() |> then(fn {:ok, _} -> :ok end)
      end
    else
      :ok
    end
  end
end
