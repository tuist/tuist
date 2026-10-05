defmodule Tuist.Tests.Coverage.Workers.DeltaWorker do
  @moduledoc """
  Writes a complete commit's coverage file deltas and targets
  (`Tuist.Tests.Coverage.Deltas.write/3`), queued when its coverage is
  published complete, when a refold changes it, when its place on the
  first-parent tree moves, and when the rows below it change.

  One pending job per commit: a request while one waits is folded into it.
  A request while one runs gets a job of its own, since what the running
  one read may predate it; uniqueness never reaches executing jobs, which is
  how `CommitWorker` once lost reports. A project's writes take turns, each
  waiting for the project's lock.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:project_id, :git_commit_sha], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Deltas

  require Logger

  @delay_seconds 10
  @unavailable_attempts 3

  def enqueue(project_id, sha) do
    %{project_id: project_id, git_commit_sha: sha}
    |> new(schedule_in: @delay_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "git_commit_sha" => sha}, attempt: attempt}) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        :ok

      project ->
        case Deltas.with_project_lock(project_id, fn -> Deltas.write(project, sha) end) do
          # The runs' rows may not have reached this replica yet, or a run
          # landed after the published fold, whose refold queues the commit
          # again. Past a few tries they are gone.
          :unavailable when attempt < @unavailable_attempts ->
            {:snooze, 30}

          :unavailable ->
            Logger.info("Coverage deltas of #{sha} not written: its runs' rows do not add up to its totals")
            :ok

          _written ->
            :ok
        end
    end
  end
end
