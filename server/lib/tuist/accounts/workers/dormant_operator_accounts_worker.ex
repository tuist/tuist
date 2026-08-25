defmodule Tuist.Accounts.Workers.DormantOperatorAccountsWorker do
  @moduledoc """
  Daily sweep that retires dormant Tuist operator user IDs.

  See `Tuist.Accounts.Dormancy` for the thresholds, for why customer
  accounts are out of scope, and for why an interrupted run is safe to
  re-run as-is.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {23, :hours}, states: :incomplete]

  alias Tuist.Accounts.Dormancy

  @snooze_seconds 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # A failed sweep raises rather than returning an error tuple, so Oban
    # records the exception and retries. What is worth acting on here is a
    # run that filled its window: come back shortly and take the next one
    # instead of leaving the remainder until tomorrow.
    case Dormancy.sweep() do
      %{more_pending: true} -> {:snooze, @snooze_seconds}
      %{} -> :ok
    end
  end
end
