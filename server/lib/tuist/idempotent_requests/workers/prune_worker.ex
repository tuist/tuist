defmodule Tuist.IdempotentRequests.Workers.PruneWorker do
  @moduledoc """
  Deletes expired idempotent-request claims and refresh-token replay entries.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60, states: :incomplete]

  alias Tuist.Authentication.RefreshReplays
  alias Tuist.IdempotentRequests

  @impl Oban.Worker
  def perform(_job) do
    RefreshReplays.prune()
    if IdempotentRequests.prune() == IdempotentRequests.prune_batch_size(), do: {:snooze, 1}, else: :ok
  end
end
