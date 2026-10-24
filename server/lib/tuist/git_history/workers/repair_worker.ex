defmodule Tuist.GitHistory.Workers.RepairWorker do
  @moduledoc """
  Repairs what a commit's late arrival left behind, queued by
  `Tuist.GitHistory.record_commits/3` when an upload stored a commit whose
  child was stored at most a day before it
  (`Tuist.GitHistory.late_children/2`): the refs that numbered the child as
  if it connected to nothing are placed again
  (`Tuist.GitHistory.replace_children/2`), and the descendants whose fold
  found no ancestor fold again
  (`Tuist.Tests.Coverage.Commits.refold_descendants/2`), after the refs moved
  and outside their lock.

  Only an upload that fills such a gap queues one, which is rare (a run whose
  parent no other run uploaded yet), so jobs are not merged per repository.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.GitHistory
  alias Tuist.Tests.Coverage.Commits

  def enqueue(repository_id, shas), do: %{repository_id: repository_id, shas: shas} |> new() |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository_id" => repository_id, "shas" => shas}}) do
    GitHistory.replace_children(repository_id, shas)
    Commits.refold_descendants(repository_id, shas)
    :ok
  end
end
