defmodule Tuist.GitHistory.Workers.FileChangesWorker do
  @moduledoc """
  Writes a listed commit's file changes (`Tuist.GitHistory.FileChanges.write/2`),
  queued when its listing is stored and when its place on the first-parent
  tree moves.

  One pending job per commit: a request while one waits is folded into it,
  and one while it runs gets a job of its own, since what the running one
  read may predate it. A commit that moved comes back after the commits below
  it that are queued to move.

  A write is not given up while it can still be done. A listing whose files
  have not all reached the replica the write reads (`:unavailable`) brings the
  job back, half a minute later at first and then less and less often, up to
  once an hour, until they add up or the listing expires. A write fails while
  a ClickHouse replica is away (its inserts wait for every replica), so the
  attempts span about an hour; one that failed them all, or whose job was
  lost, is queued again by the daily
  `Tuist.GitHistory.FileChanges.enqueue_unwritten/0`.

  A repository's writes take turns under its ref lock,
  on the coverage deltas' queue so a burst for one repository (a rebuild of
  its refs) holds none of the `:default` queue's slots.
  """
  use Oban.Worker,
    queue: :coverage_deltas,
    max_attempts: 12,
    unique: [keys: [:repository_id, :sha], states: [:available, :scheduled], period: :infinity]

  import Ecto.Query

  alias Tuist.GitHistory.FileChanges
  alias Tuist.Repo

  @deferred_seconds 5
  @unavailable_seconds 30
  @unavailable_seconds_limit 3_600

  def enqueue(repository_id, sha, opts \\ []) do
    %{repository_id: repository_id, sha: sha}
    |> new(opts)
    |> Oban.insert()
  end

  @doc "Whether a write is queued or running for any of the commits."
  def queued?(repository_id, shas) do
    Repo.exists?(
      from(j in Oban.Job,
        where: j.worker == ^Oban.Worker.to_string(__MODULE__),
        where: j.state in ["available", "scheduled", "retryable", "executing"],
        where: fragment("(?->>'repository_id')::bigint = ?", j.args, ^repository_id),
        where: fragment("?->>'sha'", j.args) in ^shas
      )
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository_id" => repository_id, "sha" => sha}, attempt: attempt}) do
    case FileChanges.write(repository_id, sha) do
      # The listing's files have not all reached this replica yet. Once the
      # listing expired the write answers `:skipped`, which ends the job.
      :unavailable ->
        {:snooze, unavailable_seconds(attempt)}

      # A commit below it moves first; this one comes back after it.
      :deferred ->
        enqueue(repository_id, sha, schedule_in: @deferred_seconds)
        :ok

      _written ->
        :ok
    end
  end

  defp unavailable_seconds(attempt),
    do: min(@unavailable_seconds * Integer.pow(2, min(attempt - 1, 10)), @unavailable_seconds_limit)
end
