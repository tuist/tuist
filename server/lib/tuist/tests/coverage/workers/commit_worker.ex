defmodule Tuist.Tests.Coverage.Workers.CommitWorker do
  @moduledoc """
  Republishes a commit's coverage (`Tuist.Tests.Coverage.Commits.recompute/2`)
  a few seconds after a run reported coverage for it, so the shards and runs
  that land together are folded once. One pending job per commit: a later
  report pushes the same job back rather than adding another.

  Debouncing must never cost a report its fold. A report that lands while the
  fold is already running cannot be in what that fold read, and the job it
  would be deduped into is the one running, so it gets a job of its own
  (`enqueue/2`); and a fold that sees the commit's runs change under it folds
  once more before it finishes. Without both, a commit measured by two schemes
  seconds apart keeps whichever the fold happened to read, for good.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :git_commit_sha], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Commits

  @delay_seconds 5

  def enqueue(project_id, sha) do
    args = %{project_id: project_id, git_commit_sha: sha}

    case args |> new(schedule_in: @delay_seconds, replace: [scheduled: [:scheduled_at]]) |> Oban.insert() do
      {:ok, %Oban.Job{state: state}} when state not in ["available", "scheduled"] ->
        args |> new(schedule_in: @delay_seconds, unique: false) |> Oban.insert()

      other ->
        other
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "git_commit_sha" => sha}}) do
    case Projects.get_project_by_id(project_id) do
      nil -> :ok
      project -> fold(project, sha)
    end

    :ok
  end

  # A report published while the fold was reading is in neither what it folded
  # nor a job of its own yet, so the fold looks once more before it finishes.
  defp fold(project, sha, rounds \\ 2) do
    folded = Commits.recompute(project, sha)

    if rounds > 1 and folded != nil and Commits.run_ids(project.id, sha) != folded.test_run_ids do
      fold(project, sha, rounds - 1)
    else
      :ok
    end
  end
end
