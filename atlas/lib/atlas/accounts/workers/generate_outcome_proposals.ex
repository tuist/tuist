defmodule Atlas.Accounts.Workers.GenerateOutcomeProposals do
  @moduledoc """
  Generates human-reviewable outcome proposals for one account.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl true
  def perform(%Oban.Job{}), do: {:cancel, :customer_outcomes_retired}
end
