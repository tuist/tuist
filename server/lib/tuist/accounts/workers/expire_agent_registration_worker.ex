defmodule Tuist.Accounts.Workers.ExpireAgentRegistrationWorker do
  @moduledoc """
  Expires an unclaimed auth.md registration when its outer claim window closes.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      keys: [:registration_id],
      states: [:available, :scheduled, :executing, :retryable],
      period: :infinity
    ]

  alias Tuist.Accounts.AgentAuth

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"registration_id" => registration_id}}) do
    AgentAuth.expire_protocol_registration(registration_id)
  end
end
