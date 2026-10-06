defmodule Tuist.Tests.Coverage.Workers.DeltaBackfillWorker do
  @moduledoc """
  Writes the coverage file deltas of one project's complete commits from
  before the deltas existed (`Tuist.Tests.Coverage.Deltas.backfill/1`).
  Queued once per project by the migration that ships them. Where a server
  can start before the ClickHouse migrations finished (an install that does
  not migrate ahead of its rollout), the missing tables fail the job and it
  runs again later.
  """
  use Oban.Worker, queue: :coverage_deltas, max_attempts: 20

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Deltas

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        :ok

      project ->
        counts = Deltas.backfill(project)

        Logger.info(
          "Coverage deltas of project #{project_id}: #{counts.written} commits written, #{counts.unavailable} without their runs' rows"
        )

        :ok
    end
  end
end
