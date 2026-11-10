defmodule Atlas.Orbit.Workers.RunThread do
  @moduledoc """
  Executes one queued thread run. `Runs.execute/2` only starts runs that
  are still queued, so a duplicate, retried, or rescued job is a no-op. A run
  checkpointed by a deploy or a lost replica is re-queued with a new `resume`
  number, which is part of the uniqueness key. Completed jobs do not block a
  re-enqueue, so `Runs.recover_queued/0` can replace a job that was lost.
  """

  use Oban.Worker,
    queue: :orbit,
    max_attempts: 3,
    unique: [
      keys: [:run_id, :resume],
      period: :infinity,
      states: :incomplete
    ]

  alias Atlas.Orbit.Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    Runs.execute(run_id)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
