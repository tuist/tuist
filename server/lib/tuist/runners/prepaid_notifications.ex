defmodule Tuist.Runners.PrepaidNotifications do
  @moduledoc """
  Threshold notices based on actual job usage, not Stripe's invoice-finalized
  credit balance. This is reporting only: dispatch and metering are unchanged.
  Applied pools cannot overlap; each pool therefore owns its term's paid usage.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.UsagePricing
  alias Tuist.RemoteExecution.Usage, as: RemoteExecutionUsage
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.PrepaidActivation
  alias Tuist.Runners.PrepaidNotification
  alias Tuist.Runners.PrepaidTopUp
  alias Tuist.Runners.Trials
  alias Tuist.Runners.Workers.PrepaidNotificationWorker
  alias Tuist.Runners.Workers.PrepaidUsageWorker

  @batch_size 100

  # Keyset pages bound each scanner job. Persist both fan-out and continuation
  # together so a failed scanner cannot silently lose the remainder of a page.
  def scan(after_id \\ 0) do
    now = DateTime.utc_now()
    today = now |> DateTime.to_date() |> Date.to_iso8601()

    ids =
      Repo.all(
        from(a in PrepaidActivation,
          where: a.id > ^after_id and a.status == "applied" and a.activated_at <= ^now,
          where: fragment("?->>'starts_on'", a.request) <= ^today,
          where: fragment("?->>'expires_on'", a.request) >= ^today,
          order_by: a.id,
          limit: @batch_size,
          select: a.id
        )
      )

    case Repo.transaction(fn ->
           Enum.each(ids, fn id ->
             %{activation_id: id} |> PrepaidUsageWorker.new() |> Oban.insert!()
           end)

           if length(ids) == @batch_size do
             %{after_id: List.last(ids)} |> PrepaidUsageWorker.new() |> Oban.insert!()
           end
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def active?(activation, account, now) do
    activation.status == "applied" && not is_nil(activation.activated_at) &&
      not DateTime.after?(activation.activated_at, now) &&
      not DateTime.after?(midnight(activation.request["starts_on"]), now) &&
      DateTime.before?(now, expires_at(activation)) && not Trials.on_trial?(account) &&
      Repo.exists?(from(s in Subscription, where: s.account_id == ^account.id and s.status in ["active", "trialing"]))
  end

  # The pool's credit and its applied top-ups', which expire with it. Each
  # top-up grant pays for one platform only, so the total is a notice
  # threshold, not what any one platform could still run on.
  def budget_cents(activation) do
    top_ups =
      Repo.all(
        from(t in PrepaidTopUp, where: t.activation_id == ^activation.id and t.status == "applied", select: t.request)
      )

    top_ups
    |> Enum.flat_map(& &1["grants"])
    |> Enum.map(&granted_cents(&1["paid_cents"], &1["credit_multiplier"]))
    |> Enum.sum()
    |> Kernel.+(granted_cents(activation.request["paid_cents"], activation.request["credit_multiplier"]))
  end

  defp granted_cents(paid_cents, credit_multiplier) do
    basis_points = credit_multiplier |> Decimal.new() |> Decimal.mult(10_000) |> Decimal.to_integer()
    div(paid_cents * basis_points, 10_000)
  end

  def threshold(_usage, budget) when budget <= 0, do: nil
  def threshold(usage, budget) when usage >= budget, do: 100
  def threshold(usage, budget) when usage * 100 >= budget * 80, do: 80
  def threshold(_usage, _budget), do: nil

  def usage_cents(activation, account, now \\ DateTime.utc_now()) do
    trial_end = account.runner_trial_ended_at
    starts_at = latest([activation.activated_at, midnight(activation.request["starts_on"]), trial_end])
    ends_at = earliest([now, expires_at(activation)])
    platforms = Enum.filter([:macos, :linux], &(to_string(&1) in activation.request["platforms"]))

    # Sum milliseconds across cycles before pricing so tiny Linux amounts do
    # not disappear at every monthly boundary. Only the final total is cents.
    units =
      account
      |> Billing.recent_billing_periods(14)
      |> Enum.reduce(%{}, fn {cycle_start, cycle_end}, totals ->
        from = latest([starts_at, cycle_start])
        until = earliest([ends_at, cycle_end])

        if DateTime.before?(from, until) do
          paid_start = latest([cycle_start, trial_end])
          previous = units_by_platform(account.id, paid_start, from)
          current = units_by_platform(account.id, from, until)

          platforms
          |> Enum.reduce(totals, fn platform, acc ->
            # Earlier paid usage spends the cycle's allowance first. Trial
            # usage does not, and activation must not reset the free tier.
            remaining_free = max(Allowance.free_monthly_minutes(platform) * 60_000 - Map.get(previous, platform, 0), 0)
            billable = max(Map.get(current, platform, 0) - remaining_free, 0)
            Map.update(acc, platform, billable, &(&1 + billable))
          end)
          |> add_cache_usage(activation, account.id, {cycle_start, from, until})
        else
          totals
        end
      end)

    # Pricing a large exact multiple preserves fractions of a cent across
    # platforms without duplicating the on-demand rate card or using floats.
    units
    |> Enum.map(fn
      {:cache, scaled_cents} -> scaled_cents
      {platform, ms} -> Prepaid.on_demand_cost_for_milliseconds(platform, ms * 6_000_000).amount
    end)
    |> Enum.sum()
    |> div(6_000_000)
  end

  # A pool that covers cache usage pays for it from the same credit, at the
  # list rates Stripe charges past each allowance, so it counts here too, in
  # cents scaled by 6,000,000 like the runner total. Usage earlier in the cycle
  # spends the allowance first, so activation never resets the free tier.
  defp add_cache_usage(totals, %{request: %{"covers_cache" => true}}, account_id, {cycle_start, from, until}) do
    previous = UsagePricing.metered_cache_usage(account_id, cycle_start, from)
    current = UsagePricing.metered_cache_usage(account_id, from, until)
    quantities = %{"cache_egress_megabytes" => :egress_megabytes, "cache_requests" => :requests}

    scaled_cents =
      UsagePricing.meter_prices()
      |> Enum.filter(&Map.has_key?(quantities, &1.event_name))
      |> Enum.map(fn meter ->
        key = Map.fetch!(quantities, meter.event_name)
        before = Map.fetch!(previous, key)
        billable = max(before + Map.fetch!(current, key) - meter.included, 0) - max(before - meter.included, 0)
        div(billable * meter.cents * 6_000_000, meter.per_units)
      end)
      |> Enum.sum()

    Map.update(totals, :cache, scaled_cents, &(&1 + scaled_cents))
  end

  defp add_cache_usage(totals, _activation, _account_id, _window), do: totals

  def enqueue(activation_id) do
    Repo.transaction(fn ->
      # Shared database lock serializes scanners on every replica. The unique
      # ledger key outlives Oban pruning and successful deliveries never reopen.
      activation = Repo.one(from(a in PrepaidActivation, where: a.id == ^activation_id, lock: "FOR UPDATE"))
      account = activation && Repo.get!(Account, activation.account_id)
      now = DateTime.truncate(DateTime.utc_now(), :second)

      if activation && active?(activation, account, now) do
        usage = usage_cents(activation, account, now)
        budget = budget_cents(activation)

        if threshold = threshold(usage, budget) do
          enqueue_recipients(account, activation, now, threshold, usage, budget)
        end
      end
    end)
  end

  defp enqueue_recipients(account, activation, now, threshold, usage, budget) do
    notifications =
      account
      |> AirUsageNotifications.recipients()
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn user ->
        %{
          activation_id: activation.id,
          account_id: account.id,
          user_id: user.id,
          threshold: threshold,
          usage_cents: usage,
          budget_cents: budget,
          inserted_at: now,
          updated_at: now
        }
      end)

    notifications
    |> Enum.chunk_every(1_000)
    |> Enum.each(fn batch ->
      Repo.insert_all(PrepaidNotification, batch,
        on_conflict: :nothing,
        conflict_target: [:activation_id, :user_id, :threshold]
      )
    end)

    recipient_ids = Enum.map(notifications, & &1.user_id)

    from(n in PrepaidNotification,
      where: n.activation_id == ^activation.id and n.user_id in ^recipient_ids and n.threshold == ^threshold,
      where: is_nil(n.delivered_at),
      order_by: n.id,
      lock: "FOR UPDATE",
      select: n.id
    )
    |> Repo.all()
    |> enqueue_pending()
  end

  defp enqueue_pending([]), do: :ok

  defp enqueue_pending(ids) do
    worker = Oban.Worker.to_string(PrepaidNotificationWorker)
    string_ids = Enum.map(ids, &to_string/1)

    active_ids =
      from(j in Oban.Job,
        where: j.worker == ^worker and j.state not in ["completed", "cancelled", "discarded"],
        where: fragment("?->>'notification_id'", j.args) in ^string_ids,
        select: j.args
      )
      |> Repo.all()
      |> MapSet.new(& &1["notification_id"])

    ids
    |> Stream.reject(&MapSet.member?(active_ids, &1))
    |> Stream.map(&PrepaidNotificationWorker.new(%{notification_id: &1}))
    |> Stream.chunk_every(1_000)
    |> Enum.each(&Oban.insert_all/1)
  end

  defp units_by_platform(account_id, from, until) do
    if DateTime.before?(from, until) do
      account_id |> RemoteExecutionUsage.metered_units_by_platform(from, until) |> Map.new(&{&1.platform, &1.total_units})
    else
      %{}
    end
  end

  defp expires_at(activation),
    do: activation.request["expires_on"] |> Date.from_iso8601!() |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

  defp midnight(date), do: date |> Date.from_iso8601!() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  defp latest(dates), do: dates |> Enum.reject(&is_nil/1) |> Enum.max(DateTime)
  defp earliest(dates), do: Enum.min(dates, DateTime)
end
