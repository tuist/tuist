defmodule Atlas.Engineering.Errors.SummaryWorker do
  @moduledoc """
  Reconciles the current error-summary reporting period and delivers it.

  TODO(atlas): summary generation and delivery are not implemented yet.
  Hive drives this through LangChain + Slack; Atlas has neither wired up
  here. The worker is registered as a stub so the schedule can still be
  configured and swept.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Atlas.Engineering.Errors.SummaryWorker: summary generation not yet implemented")
    :ok
  end
end
