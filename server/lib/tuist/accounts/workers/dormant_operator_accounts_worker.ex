defmodule Tuist.Accounts.Workers.DormantOperatorAccountsWorker do
  @moduledoc """
  Daily sweep that retires dormant Tuist operator user IDs.

  See `Tuist.Accounts.Dormancy` for the thresholds and for why customer
  accounts are out of scope.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {23, :hours}, states: [:available, :scheduled, :executing]]

  alias Tuist.Accounts.Dormancy

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Dormancy.sweep()

    :ok
  end
end
