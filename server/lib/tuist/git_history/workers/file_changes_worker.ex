defmodule Tuist.GitHistory.Workers.FileChangesWorker do
  @moduledoc """
  Writes a listed commit's file changes (`Tuist.GitHistory.FileChanges.write/2`),
  queued when its listing is stored and when its place on the first-parent
  tree moves.

  One pending job per commit: a request while one waits is folded into it,
  and one while it runs gets a job of its own, since what the running one
  read may predate it. A repository's writes take turns under its ref lock,
  on the coverage deltas' queue so a burst for one repository (a rebuild of
  its refs) holds none of the `:default` queue's slots.
  """
  use Oban.Worker,
    queue: :coverage_deltas,
    max_attempts: 5,
    unique: [keys: [:repository_id, :sha], states: [:available, :scheduled], period: :infinity]

  alias Tuist.GitHistory.FileChanges

  require Logger

  @unavailable_attempts 3

  def enqueue(repository_id, sha) do
    %{repository_id: repository_id, sha: sha}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository_id" => repository_id, "sha" => sha}, attempt: attempt}) do
    case FileChanges.write(repository_id, sha) do
      # The listing's files may not have reached this replica yet.
      :unavailable when attempt < @unavailable_attempts ->
        {:snooze, 30}

      :unavailable ->
        Logger.info("File changes of #{sha} not written: its listing's files do not add up to its file count")
        :ok

      _written ->
        :ok
    end
  end
end
