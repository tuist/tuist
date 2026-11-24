defmodule Tuist.TestImpactAnalysis.Workers.SnapshotBackfillWorker do
  @moduledoc """
  Writes the test maps of one project's commits measured within the maps'
  retention from their runs' retained evidence
  (`Tuist.TestImpactAnalysis.Snapshots.backfill/2`). Queued once per project
  by the migration that ships it. Where a server can start before the
  ClickHouse migrations finished, the missing tables fail the job and it
  runs again later. Writes are idempotent, so overlapping with live folds
  or a rerun writes nothing twice.
  """
  use Oban.Worker, queue: :coverage_deltas, max_attempts: 20

  alias Tuist.Projects
  alias Tuist.TestImpactAnalysis.Snapshots

  require Logger

  @days 31

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        :ok

      project ->
        :ok = Snapshots.backfill(project, @days)
        Logger.info("Test maps of project #{project_id} for the last #{@days} days recorded")
        :ok
    end
  end
end
