defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorker do
  @moduledoc """
  Snapshots a customer's meter values for the parent billing period
  and fans out one Stripe reporting job per meter.

  A customer that earned nothing over the period finishes without
  reaching Stripe at all, which is the common case: the billable
  customer list is far larger than the set with usage on any given day.
  """
  # A boundary lookup that can't reach Stripe fails the job instead of
  # snapshotting an unsplit window, so retries have to finish while the
  # usage can still land on the right invoice. With Oban's default
  # `attempt^4 + 15` backoff, 12 attempts exhaust in ~11h, inside the
  # invoice-finalization grace period (Billing settings, up to 72h) that
  # this reporting delay already has to fit within.
  use Oban.Worker, max_attempts: 12

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"customer_id" => customer_id, "period_start" => period_start, "period_end" => period_end}
      }) do
    sync(
      customer_id,
      DateTime.from_unix!(period_start, :microsecond),
      DateTime.from_unix!(period_end, :microsecond)
    )
  end

  # Transitional clause for jobs enqueued by the pre-fan-out parent worker,
  # which carried only the customer id. During a rolling deploy those jobs
  # can still be draining from the queue; without this clause a new-code node
  # would raise FunctionClauseError on them, exhaust their retries, and
  # silently drop a day of usage for that customer. We recompute the period
  # the same way the parent now does (yesterday's half-open day). Safe to
  # remove once no pre-deploy jobs remain in the queue.
  def perform(%Oban.Job{args: %{"customer_id" => customer_id}}) do
    period_end = Timex.beginning_of_day(DateTime.utc_now())
    period_start = Timex.shift(period_end, days: -1)
    sync(customer_id, period_start, period_end)
  end

  defp sync(customer_id, %DateTime{} = period_start, %DateTime{} = period_end) do
    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{
        customer_id: customer_id,
        period_start: period_start,
        period_end: period_end
      })
    end

    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)

    include_qa = FunWithFlags.enabled?(:qa_billing_enabled, for: account)
    day = {period_start, period_end}

    # Measure the whole day before looking up any boundary. Meter values are
    # sums of non-negative usage, so a day that earned nothing has no
    # sub-window that earned anything either, and there is nothing to
    # attribute to either side of a boundary. Most billable customers are
    # idle on any given day, and boundary discovery costs a Stripe request
    # each, so this is what keeps the nightly run off Stripe's rate limit.
    case Billing.customer_meter_values(account, period_start, period_end, include_qa: include_qa) do
      [] ->
        :ok

      day_values ->
        # Snapshot each service period the day covers separately. A day that
        # straddles a subscription renewal, its cancellation, or the end of a
        # runner trial produces one set of jobs per side, each reporting only
        # the usage its own period earned, so no event ever crosses an invoice
        # boundary.
        #
        # A failed boundary lookup fails the whole job rather than snapshotting
        # the day as one window. The snapshot is permanent — a child never
        # re-queries usage — so guessing the boundary wrong here cannot be
        # corrected later.
        with {:ok, windows} <- Billing.usage_windows(account, period_start, period_end) do
          windows
          |> Enum.flat_map(fn
            # No boundary fell inside the day, so the only window is the one
            # already measured above and re-aggregating it would just repeat
            # the same ClickHouse work.
            ^day -> meter_jobs(customer_id, day, day_values)
            window -> meter_jobs(customer_id, window, window_values(account, window, include_qa))
          end)
          |> Oban.insert_all()

          :ok
        end
    end
  end

  defp window_values(account, {window_start, window_end}, include_qa) do
    Billing.customer_meter_values(account, window_start, window_end, include_qa: include_qa)
  end

  defp meter_jobs(customer_id, {window_start, window_end}, values) do
    Enum.map(values, fn meter ->
      SyncCustomerStripeMeterWorker.new(%{
        customer_id: customer_id,
        event_name: meter.event_name,
        value: meter.value,
        period_start: DateTime.to_unix(window_start, :microsecond),
        period_end: DateTime.to_unix(window_end, :microsecond)
      })
    end)
  end
end
