defmodule Tuist.Billing.Workers.RefreshSubscriptionPeriodsWorker do
  @moduledoc """
  Fans out a period refresh for every active subscription whose mirrored
  service period is missing or has already closed.

  The mirrored period is written by the subscription webhooks, which
  leaves two gaps this closes. Rows that predate the columns hold no
  period until their subscription next emits an event, and an annual
  term can go a year without one. A renewal whose webhook is late, lost,
  or delivered out of order leaves a closed period behind.

  Neither gap is a correctness problem, because a period that is missing
  or closed is not served: `Billing.current_billing_period/1` reads
  Stripe instead. They are a cost problem, and the cost is paid per page
  render rather than once. Sweeping on a schedule keeps that fallback
  rare instead of permanent for whichever rows are unlucky.

  Idempotent and self-limiting: once every row holds the period that is
  running, this is one indexed read and no Stripe traffic at all.
  """
  use Oban.Worker

  alias Tuist.Billing
  alias Tuist.Billing.Workers.RefreshSubscriptionPeriodWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Inserted one at a time rather than through `insert_all`, which does
    # not enforce uniqueness on Oban's basic engine. That uniqueness is
    # the whole defence against a Stripe outage stacking one sweep's
    # worth of duplicate work per hour on top of the jobs already
    # retrying, so losing it silently would defeat the point.
    Enum.each(Billing.subscription_ids_with_stale_period(), fn subscription_id ->
      Oban.insert(RefreshSubscriptionPeriodWorker.new(%{subscription_id: subscription_id}))
    end)

    :ok
  end
end
