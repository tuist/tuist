defmodule Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker do
  @moduledoc """
  Turns a paid prepaid invoice into a Stripe credit grant.

  The job carries only the invoice id and re-reads the invoice from
  Stripe on every attempt, rather than freezing the webhook's copy into
  its args. A retry then sees the invoice as it stands now, so a
  metadata term corrected after the fact — a mistyped funding ratio, a
  missing platform scope — is picked up by the retry instead of being
  replayed wrong.

  Runs for every paid invoice, not only ones that look prepaid, because
  the webhook payload carries at most the first handful of an invoice's
  lines and a prepaid line further down a busy bill would otherwise go
  unseen. `Tuist.Runners.Prepaid` pages the lines endpoint and decides
  on the full picture; an ordinary invoice costs one cheap no-op.

  Uniqueness is on the invoice id for all time, so Stripe redelivering
  `invoice.paid` cannot enqueue a second run. That is the outermost of
  three layers: Oban drops the duplicate job, each request carries an
  idempotency key derived from the invoice and line, and
  `Tuist.Runners.Prepaid` checks Stripe for a grant against the same
  line before creating one. Oban prunes completed jobs eventually and
  Stripe expires idempotency keys after 24h, so only the innermost
  check holds indefinitely — and granting money twice is worth all
  three.
  """
  use Oban.Worker,
    max_attempts: 10,
    unique: [keys: [:invoice_id], period: :infinity]

  alias Tuist.Runners.Prepaid

  require Logger

  # Retry cadence while the runner Prices do not exist yet. Snoozing
  # does not consume an attempt, so the grant stays owed rather than
  # being discarded before someone can create the Price.
  @price_retry_seconds 3600
  # ~3 days of snoozing. Past that the misconfiguration needs a human,
  # so let the job fail into alerting instead of snoozing in silence.
  @max_price_snoozes 72

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invoice_id" => invoice_id}, attempt: attempt}) do
    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{invoice_id: invoice_id})
    end

    with {:ok, invoice} <- Stripe.Invoice.retrieve(invoice_id) do
      invoice
      |> Prepaid.grant_for_paid_invoice()
      |> handle_result(invoice_id, attempt)
    end
  end

  defp handle_result({:ok, :not_prepaid}, invoice_id, _attempt) do
    Logger.info("runners: invoice #{invoice_id} carries no prepaid line, no credit granted")
    :ok
  end

  defp handle_result({:ok, grants}, invoice_id, _attempt) when is_list(grants) do
    Logger.info("runners: granted #{length(grants)} prepaid credit grant(s) for invoice #{invoice_id}")
    :ok
  end

  defp handle_result({:error, :no_runner_prices_configured}, invoice_id, attempt) when attempt <= @max_price_snoozes do
    Logger.warning(
      "runners: prepaid invoice #{invoice_id} is paid but no runner Stripe Price is configured; " <>
        "retrying in #{@price_retry_seconds}s"
    )

    {:snooze, @price_retry_seconds}
  end

  defp handle_result(result, _invoice_id, _attempt), do: result
end
