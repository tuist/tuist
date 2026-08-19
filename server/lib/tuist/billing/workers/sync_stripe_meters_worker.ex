defmodule Tuist.Billing.Workers.SyncStripeMetersWorker do
  @moduledoc """
  Chooses one half-open billing period and queues one customer snapshot
  job per billable customer with those immutable boundaries.

  The daily cron passes no arguments and gets the previous UTC day. A
  caller can instead pass explicit `period_start` / `period_end` unix
  microsecond boundaries to re-report a day whose jobs were lost, or to
  backfill after an outage.

  Such a request must name a whole UTC day that has already closed, and
  is discarded otherwise. Both halves matter, because the Stripe event
  identifier is derived from the customer, meter, and exact window:

    * An open window would snapshot partial usage and post it under the
      identifier for the whole period. The later full report carries the
      same identifier, so Stripe deduplicates it and every minute earned
      after the snapshot is lost.

    * A closed but sub-day window gets an identifier the cron will never
      produce, so the cron's whole-day run reports that usage again and it
      is counted twice.

  A whole closed day is exactly what the cron reports, so a manual request
  deduplicates against it rather than racing it. Narrower windows still
  occur internally when `Billing.usage_windows/3` splits at a subscription
  boundary; both paths split identically, so the identifiers match.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"period_start" => period_start, "period_end" => period_end}}) do
    period_start = DateTime.from_unix!(period_start, :microsecond)
    period_end = DateTime.from_unix!(period_end, :microsecond)

    case validate_window(period_start, period_end) do
      :ok -> sync(period_start, period_end)
      {:error, reason} -> {:discard, reason}
    end
  end

  def perform(_args) do
    period_end = Timex.beginning_of_day(DateTime.utc_now())
    sync(Timex.shift(period_end, days: -1), period_end)
  end

  # Discarded rather than retried: an operator asking for the wrong window
  # wants to hear about it, and no amount of waiting makes a sub-day
  # request correct.
  defp validate_window(period_start, period_end) do
    cond do
      not midnight?(period_start) or not midnight?(period_end) ->
        {:error, :window_not_aligned_to_utc_midnight}

      DateTime.diff(period_end, period_start, :second) != 86_400 ->
        {:error, :window_is_not_one_whole_day}

      DateTime.after?(period_end, DateTime.utc_now()) ->
        {:error, :window_has_not_closed_yet}

      true ->
        :ok
    end
  end

  defp midnight?(%DateTime{hour: 0, minute: 0, second: 0, microsecond: {0, _}}), do: true
  defp midnight?(_datetime), do: false

  defp sync(%DateTime{} = period_start, %DateTime{} = period_end) do
    Accounts.list_billable_customers()
    |> Enum.map(
      &SyncCustomerStripeMetersWorker.new(%{
        customer_id: &1,
        period_start: DateTime.to_unix(period_start, :microsecond),
        period_end: DateTime.to_unix(period_end, :microsecond)
      })
    )
    |> Oban.insert_all()

    :ok
  end
end
