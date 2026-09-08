defmodule Tuist.Billing.Workers.RefreshSubscriptionPeriodWorker do
  @moduledoc """
  Mirrors one subscription's current service period from Stripe onto its
  row.
  """
  # Unique per subscription across incomplete states, so a subscription
  # already waiting on a refresh is not queued again by the next sweep.
  # Enforced at insert time, which is why the parent inserts these one at
  # a time.
  use Oban.Worker,
    unique: [
      keys: [:subscription_id],
      period: :infinity,
      states: :incomplete
    ]

  alias Tuist.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => subscription_id}}) do
    Billing.refresh_subscription_period(subscription_id)
  end
end
