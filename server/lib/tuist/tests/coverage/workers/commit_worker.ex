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

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Commits

  # The fold reads a run through its `test_runs` row, which reaches ClickHouse
  # through a buffer flushed on a tick; folding before it lands drops the run.
  def enqueue(project_id, sha), do: schedule(project_id, sha, div(Environment.clickhouse_flush_interval_ms(), 1000) + 5)

  @doc """
  Refolds the commit after the given delay. For data that belongs to runs the
  commit already folded but reached the server after them: a run's
  selective-testing results arrive with its command event, stored through a
  buffer, which a `tuist coverage complete` right after the tests outruns.
  """
  def enqueue_refold(project_id, sha, delay_seconds), do: schedule(project_id, sha, delay_seconds)

  # A pending job is pushed back to the new time, never pulled forward: the
  # later fold may be waiting for data the sooner one would miss.
  defp schedule(project_id, sha, delay_seconds) do
    args = %{project_id: project_id, git_commit_sha: sha}
    scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

    case args |> new(scheduled_at: scheduled_at) |> Oban.insert() do
      {:ok, %Oban.Job{state: state}} when state not in ["available", "scheduled"] ->
        args |> new(scheduled_at: scheduled_at, unique: false) |> Oban.insert()

      {:ok, %Oban.Job{conflict?: true, state: "scheduled"} = job} ->
        {count, _} =
          Repo.update_all(
            from(j in Oban.Job, where: j.id == ^job.id and j.state == "scheduled" and j.scheduled_at < ^scheduled_at),
            set: [scheduled_at: scheduled_at]
          )

        {:ok, if(count == 1, do: %{job | scheduled_at: scheduled_at}, else: job)}

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
