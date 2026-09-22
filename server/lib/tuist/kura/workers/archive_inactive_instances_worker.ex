defmodule Tuist.Kura.Workers.ArchiveInactiveInstancesWorker do
  @moduledoc """
  Hourly sweep that moves account-region Kura instances with no cache demand
  for a complete inactive window, or that have remained unused, into drain-pending
  (`Tuist.Kura.Lifecycle.sweep/0`).

  Only the decision lives here. Draining, teardown, archival, cancellation,
  and cold return all converge on the reconciler tick, so an account whose
  demand comes back mid-drain is served again within a tick rather than
  waiting for the next sweep.
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
