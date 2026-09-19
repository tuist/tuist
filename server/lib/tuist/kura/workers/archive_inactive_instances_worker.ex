defmodule Tuist.Kura.Workers.ArchiveInactiveInstancesWorker do
  @moduledoc """
  Daily sweep that moves account-region Kura instances with no cache demand
  for a complete inactive window into drain-pending
  (`Tuist.Kura.Lifecycle.sweep/0`).

  Only the decision lives here. Draining, teardown, archival, cancellation,
  and cold return all converge on the reconciler tick, so an account whose
  demand comes back mid-drain is served again within a tick rather than
  waiting for tomorrow's sweep.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:worker],
      period: :infinity,
      states: :incomplete
    ]

  alias Tuist.Kura.Lifecycle

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Lifecycle.sweep()
  end
end
