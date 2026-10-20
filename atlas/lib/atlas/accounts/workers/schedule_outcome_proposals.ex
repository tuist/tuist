defmodule Atlas.Accounts.Workers.ScheduleOutcomeProposals do
  @moduledoc """
  Schedules proposal generation for accounts with new evidence or stale reviews.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  @impl true
  def perform(%Oban.Job{}), do: {:cancel, :customer_outcomes_retired}
end
