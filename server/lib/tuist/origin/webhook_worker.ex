defmodule Tuist.Origin.WebhookWorker do
  @moduledoc "Reconciles verified Origin deliveries durably and idempotently."
  use Oban.Worker,
    queue: :vcs_comments,
    unique: [keys: [:deliveryId], period: 86_400, states: [:available, :scheduled, :executing, :retryable, :completed]]

  alias Tuist.Origin

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: Origin.handle_webhook(args)
end
