defmodule Tuist.Runners.Allowance do
  @moduledoc """
  The free monthly runner allowance, and whether an account may keep
  dispatching once it is spent.

  Every plan gets the same allowance, because it is a tier on the runner
  Price rather than a plan attribute: the first
  `free_monthly_minutes/0` baseline machine-minutes of each billing
  period cost nothing, and usage past that is charged at the standard
  rate. What differs by plan is whether exceeding it is *possible*.

  A paid plan can exceed it and be billed for the excess. A free account
  cannot: it has no subscription for the excess to land on, so without a
  cap its runner usage would be unbounded and unbillable. That is the
  one thing this module enforces.

  ## Why the cap is here and not in the Price

  Stripe can express the free tier but not refuse the work. The Price
  stops charging below the allowance; only dispatch can stop a job from
  running past it. The two have to agree, so
  `free_monthly_minutes/0` and the Price's first tier are the same
  number stated twice, and have to be changed together — the same
  hand-kept duplication `Tuist.Billing`'s `@unit_prices` carries.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Billing, as: RunnerBilling
  alias Tuist.Runners.Prepaid

  # Must match the first tier of that environment's runner Price. The
  # default is the real allowance; staging lowers both together so the
  # cap and the paid tier can be reached without burning a hundred
  # minutes of real Mac time to get there. Lowering only this would move
  # the cap without moving the Price, so an account would be cut off
  # before it could ever reach the charged tier.
  @default_free_monthly_minutes 100

  # Dispatch is a hot path and this adds an aggregate over
  # `runner_sessions` to it, so the answer is cached briefly. The cost is
  # that an account can overshoot by whatever it starts inside the TTL;
  # the cap is a spend control, not a hard quota, and bounded overshoot
  # is the right trade against querying on every claim.
  @usage_cache_ttl to_timeout(second: 30)

  @doc """
  Baseline machine-minutes every account gets free each billing period.
  """
  def free_monthly_minutes do
    Application.get_env(:tuist, :runner_free_monthly_minutes, @default_free_monthly_minutes)
  end

  @doc """
  True when `account` must not be given another runner job.

  Only ever true for an account with no paid plan. A paid account is
  never blocked: going past the allowance is exactly what it is billed
  for.
  """
  def exhausted?(%Account{} = account) do
    case Billing.effective_plan(account) do
      :air -> minutes_used(account) >= free_monthly_minutes()
      _plan -> false
    end
  end

  @doc """
  Whole baseline machine-minutes `account` has used in the current
  calendar month.

  Truncated, so an account is only cut off once it has fully spent the
  allowance rather than partway through the minute that crosses it. The
  Price itself charges proportionally and does no such rounding; this is
  a dispatch decision, not a billing one.

  Calendar month rather than the Stripe billing period because the
  accounts this gates have no subscription, so there is no period to
  read. For a paid account the figure is only ever advisory: nothing is
  blocked on it.
  """
  def minutes_used(%Account{id: account_id}) do
    KeyValueStore.get_or_update(
      [:runner_allowance, account_id],
      [ttl: @usage_cache_ttl],
      fn ->
        now = DateTime.utc_now()
        month_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}

        account_id
        |> RunnerBilling.compute_milliseconds(month_start, now)
        |> div(60_000)
      end
    )
  end

  @doc """
  This calendar month's runner usage broken down by day, with what each
  day's time is worth and what of it is actually billable.

  Scoped to the calendar month rather than an arbitrary range because
  the allowance resets monthly: the same day's usage is free or charged
  depending on how much of the month preceded it, so a window that does
  not start where the allowance does cannot answer what was billed.

  The allowance is consumed in date order, so the days that cross it
  carry a gross figure larger than their billed one and the days before
  it bill nothing. That split is the point: it shows where the free tier
  ran out rather than presenting one blended number.
  """
  def monthly_breakdown(%Account{id: account_id}) do
    now = DateTime.utc_now()
    period_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}
    free_ms = free_monthly_minutes() * 60_000

    per_day =
      account_id
      |> RunnerBilling.compute_milliseconds_per_bucket(period_start, now, :day)
      |> Enum.sort_by(fn {date, _ms} -> Date.to_erl(date) end)

    {days, _remaining} =
      Enum.map_reduce(per_day, free_ms, fn {date, ms}, remaining_free ->
        covered = min(ms, remaining_free)
        billable = ms - covered

        day = %{
          # The table keys rows on `:id`; without one every row shares a
          # DOM id and LiveView cannot patch the list.
          id: Date.to_iso8601(date),
          date: date,
          minutes: div(ms, 60_000),
          gross: Prepaid.on_demand_cost_for_milliseconds(ms),
          billed: Prepaid.on_demand_cost_for_milliseconds(billable)
        }

        {day, remaining_free - covered}
      end)

    total_ms = per_day |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(now),
      minutes: div(total_ms, 60_000),
      free_minutes: free_monthly_minutes(),
      gross: Prepaid.on_demand_cost_for_milliseconds(total_ms),
      billed: Prepaid.on_demand_cost_for_milliseconds(max(total_ms - free_ms, 0)),
      days: Enum.reject(days, &(&1.minutes == 0 and &1.gross == Money.new(0, :USD))),
      platforms: platform_rows(account_id, period_start, now, total_ms)
    }
  end

  # One row per platform that ran anything, shaped like the usage table
  # it feeds: what the period has used so far, where that lands by the
  # end of it, what the plan covers, and what the period before it came
  # to.
  defp platform_rows(account_id, period_start, now, total_ms) do
    previous_start = period_start |> DateTime.add(-1, :day) |> beginning_of_month()
    previous_end = DateTime.add(period_start, -1, :microsecond)

    previous_by_platform = milliseconds_by_platform(account_id, previous_start, previous_end)

    account_id
    |> milliseconds_by_platform(period_start, now)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {platform, ms} ->
      %{
        id: to_string(platform),
        platform: platform,
        minutes: div(ms, 60_000),
        projected_minutes: project(ms, now),
        # The allowance is one pot for the account rather than one per
        # platform, so it is only meaningful against a platform that has
        # a rate to spend it at. macOS is the only one so far.
        included_minutes: if(platform == :macos, do: free_monthly_minutes()),
        previous_minutes: previous_by_platform |> Map.get(platform, 0) |> div(60_000),
        gross: platform_cost(platform, ms),
        billed: platform_cost(platform, billable_milliseconds(platform, ms, total_ms))
      }
    end)
  end

  defp milliseconds_by_platform(account_id, period_start, period_end) do
    account_id
    |> RunnerBilling.compute_milliseconds_by_machine(period_start, period_end)
    |> Enum.reduce(%{}, fn usage, acc ->
      Map.update(acc, usage.platform, usage.total_ms, &(&1 + usage.total_ms))
    end)
  end

  # Only macOS has an agreed rate, so any other platform's time is real
  # but not yet priceable; it shows minutes and no money rather than a
  # number we invented.
  defp platform_cost(:macos, ms), do: Prepaid.on_demand_cost_for_milliseconds(ms)
  defp platform_cost(_platform, _ms), do: nil

  # The allowance is spent by the account, not by the platform, so a
  # platform's billable share is what is left of it after the account's
  # free milliseconds are taken off the whole period.
  defp billable_milliseconds(_platform, ms, total_ms) do
    free_ms = free_monthly_minutes() * 60_000
    billable_total = max(total_ms - free_ms, 0)

    if total_ms == 0, do: 0, else: div(ms * billable_total, total_ms)
  end

  # Straight-line: what the period has used so far, scaled to its full
  # length. Honest only as an extrapolation, which is what a projection
  # is.
  defp project(ms, now) do
    days_elapsed = now.day
    days_in_month = Date.days_in_month(DateTime.to_date(now))

    ms |> Kernel.*(days_in_month) |> div(days_elapsed) |> div(60_000)
  end

  defp beginning_of_month(%DateTime{} = datetime) do
    %{datetime | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}
  end

  @doc """
  Minutes left on `account`'s allowance, floored at zero.
  """
  def minutes_remaining(%Account{} = account) do
    max(free_monthly_minutes() - minutes_used(account), 0)
  end
end
