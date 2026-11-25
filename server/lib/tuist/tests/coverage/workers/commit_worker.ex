defmodule Tuist.Tests.Coverage.Workers.CommitWorker do
  @moduledoc """
  Republishes a commit's coverage (`Tuist.Tests.Coverage.Commits.recompute/3`)
  a few seconds after a run reported coverage for it, so the shards and runs
  that land together are folded once. One pending job per commit: a later
  report pushes the same job back rather than adding another.

  Debouncing must never cost a report its fold, and the commit's folds run
  one after another. A report that lands while a fold of the commit runs
  cannot be in what that fold read, so it gets a pending job of its own,
  which waits for that fold: when the fold has published, it releases its
  run and lets the pending job go at once. A report holds the running job's
  row (`FOR UPDATE`) until its own job is scheduled, and the release updates
  that row first, so a report sees either the fold still running, its job
  then pulled forward, or the fold released. A pending job only waits ten minutes, in case the fold's node
  died. Every report, however many, lands in the one pending job, so a
  commit has at most one fold running and one to run after it.

  A fold goes ahead only once every replica holds what it reads of the
  commit's runs (`Tuist.Tests.Coverage.RunInputs`); until then the job
  snoozes, writing nothing, or ends when a pending job will fold after it. A
  report declared while it read is gated the same way before it publishes.
  Past the inputs' deadline it folds without them, as a lower bound, and
  folds once more later in case they arrived (`enqueue_follow_up/3`).
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
  alias Tuist.Tests.Coverage.RunInputs

  @snooze_seconds 5
  @after_fold_seconds 600

  # The fold reads a run through its `test_runs` row, which reaches ClickHouse
  # through a buffer flushed on a tick; folding before it lands drops the run.
  def enqueue(project_id, sha) do
    # A running fold's row stays locked until the report's job is scheduled,
    # so the fold's release, which updates that row first, sees the job.
    {:ok, scheduled} =
      Repo.transaction(fn ->
        delay_seconds =
          if folding?(project_id, sha),
            do: @after_fold_seconds,
            else: div(Environment.clickhouse_flush_interval_ms(), 1000) + 5

        schedule(project_id, sha, delay_seconds)
      end)

    scheduled
  end

  # A pending job is pushed back to the new time, never pulled forward: the
  # runs reported so far land together in the later fold.
  defp schedule(project_id, sha, delay_seconds) do
    scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

    case %{project_id: project_id, git_commit_sha: sha} |> new(scheduled_at: scheduled_at) |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true, id: id, state: "scheduled"} = job} when not is_nil(id) ->
        {count, _} =
          Repo.update_all(
            from(j in Oban.Job, where: j.id == ^id and j.state == "scheduled" and j.scheduled_at < ^scheduled_at),
            set: [scheduled_at: scheduled_at]
          )

        {:ok, if(count == 1, do: %{job | scheduled_at: scheduled_at}, else: job)}

      # Without an id, another insert of the commit's job holds Oban's unique
      # lock: that job is the pending one.
      other ->
        other
    end
  end

  @doc """
  Folds the commit once more after a fold that went ahead without `missing`
  inputs (`Tuist.Tests.Coverage.RunInputs.status/2`), if they may still
  arrive. A fold already pending reads them as well, so it is left as is.
  """
  def enqueue_follow_up(project_id, sha, missing) do
    case RunInputs.follow_up_in(missing) do
      nil -> :skipped
      delay_seconds -> %{project_id: project_id, git_commit_sha: sha} |> new(schedule_in: delay_seconds) |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "git_commit_sha" => sha}} = job) do
    case Projects.get_project_by_id(project_id) do
      nil -> :ok
      project -> fold(project, sha, job)
    end
  end

  defp fold(project, sha, job) do
    gated_at = RunInputs.gated_at()

    case RunInputs.status(project.id, sha) do
      :wait ->
        wait(project.id, sha, job)

      status ->
        case Commits.recompute(project, sha, incomplete: status != :ready, gated_at: gated_at) do
          :wait ->
            wait(project.id, sha, job)

          _summary ->
            release(project.id, sha, job)
            with {:incomplete, missing} <- status, do: enqueue_follow_up(project.id, sha, missing)
            :ok
        end
    end
  end

  # A job waiting for the gate ends when a pending job will fold after it.
  defp wait(project_id, sha, job) do
    if release(project_id, sha, job) > 0, do: :ok, else: {:snooze, @snooze_seconds}
  end

  # Marks this run of the job released, so reports from now on schedule
  # their fold as usual, then lets the pending job go now; returns how many
  # were pending. Released is per attempt, which every run of a job
  # (snoozed, retried) bumps. In that order, each its own statement: a
  # report holding this job's row (`folding?/2`) has scheduled its job by
  # the time the first update goes through, and one that locks the row
  # after it sees the job released.
  defp release(project_id, sha, job) do
    Repo.update_all(
      from(j in Oban.Job,
        where: j.id == ^job.id,
        update: [set: [meta: fragment("? || jsonb_build_object('released', ?::int)", j.meta, ^job.attempt)]]
      ),
      []
    )

    {count, _} =
      Repo.update_all(
        from(j in commit_jobs(project_id, sha), where: j.state in ["available", "scheduled"] and j.id != ^job.id),
        set: [scheduled_at: DateTime.utc_now()]
      )

    count
  end

  # Whether a fold of the commit is running and has not published yet,
  # locking the rows of its running jobs until the caller's transaction
  # ends. In id order, so two reports never wait on each other's rows.
  defp folding?(project_id, sha) do
    from(j in commit_jobs(project_id, sha),
      where: j.state == "executing" and fragment("coalesce((?->>'released')::int, 0) < ?", j.meta, j.attempt),
      order_by: j.id,
      lock: "FOR UPDATE",
      select: j.id
    )
    |> Repo.all()
    |> Enum.any?()
  end

  defp commit_jobs(project_id, sha) do
    worker = inspect(__MODULE__)
    queue = to_string(__opts__()[:queue])

    from(j in Oban.Job,
      where:
        j.queue == ^queue and j.worker == ^worker and fragment("?->>'project_id'", j.args) == ^to_string(project_id) and
          fragment("?->>'git_commit_sha'", j.args) == ^sha
    )
  end
end
