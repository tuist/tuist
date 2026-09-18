defmodule Tuist.Tests.Coverage.Workers.CommitWorker do
  @moduledoc """
  Republishes a commit's coverage (`Tuist.Tests.Coverage.Commits.recompute/2`)
  a few seconds after a run reported coverage for it, so the shards and runs
  that land together are folded once. One pending job per commit: a later
  report pushes the same job back rather than adding another.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :git_commit_sha], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Commits

  @delay_seconds 5

  def enqueue(project_id, sha) do
    %{project_id: project_id, git_commit_sha: sha}
    |> new(schedule_in: @delay_seconds, replace: [scheduled: [:scheduled_at]])
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "git_commit_sha" => sha}}) do
    case Projects.get_project_by_id(project_id) do
      nil -> :ok
      project -> Commits.recompute(project, sha)
    end

    :ok
  end
end
