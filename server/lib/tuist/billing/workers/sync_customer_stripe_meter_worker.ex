defmodule Tuist.Billing.Workers.SyncCustomerStripeMeterWorker do
  @moduledoc """
  Reports one snapshotted customer meter value for the billing period
  chosen by the parent worker.
  """
  # Cap retries so the last attempt lands well inside Stripe's
  # deduplication window. Stripe only guarantees meter-event identifier
  # uniqueness for at least 24h and may prune request idempotency keys
  # after 24h, so a request that succeeded remotely but lost its response
  # must not be retried past that window or it would double-report usage.
  # With Oban's default `attempt^4 + 15` backoff, 12 attempts exhaust in
  # ~11h (vs. >13 days at the default of 20), staying within 24h even with
  # jitter. Failures beyond that are dropped rather than risking a
  # duplicate; sustained failures should be caught by job-error alerting.
  use Oban.Worker, max_attempts: 12

  alias Tuist.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{
        inserted_at: inserted_at,
        args: %{
          "customer_id" => customer_id,
          "event_name" => event_name,
          "value" => value,
          "period_start" => period_start,
          "period_end" => period_end
        }
      }) do
    period_start_datetime = DateTime.from_unix!(period_start, :microsecond)
    period_end_datetime = DateTime.from_unix!(period_end, :microsecond)

    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{
        customer_id: customer_id,
        event_name: event_name,
        period_start: period_start_datetime,
        period_end: period_end_datetime
      })
    end

    # The job's own insertion instant is the reporting clock. It is fixed
    # when the job is created and identical on every retry, which is what
    # the idempotency key requires: a changed timestamp under the same key
    # is rejected by Stripe as a reused key with different parameters.
    Billing.report_meter_event(
      customer_id,
      event_name,
      value,
      period_start_datetime,
      period_end_datetime,
      DateTime.from_naive!(inserted_at, "Etc/UTC")
    )
  end
end
