defmodule Tuist.Origin.WebhookWorker do
  @moduledoc "Reconciles lifecycle notifications against current Origin state, avoiding out-of-order event regressions."
  use Oban.Worker,
    queue: :vcs_comments,
    max_attempts: 5,
    unique: [
      period: 604_800,
      keys: [:delivery_id],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias Tuist.Origin

  @impl true
  def perform(%Oban.Job{args: %{"installation_id" => installation_id}}) do
    Origin.reconcile_installation(installation_id)
  end
end
