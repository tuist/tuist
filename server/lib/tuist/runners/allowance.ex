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
  alias Tuist.Runners.Trials

  # Platforms with an agreed rate. Linux joins when it has one.
  @priced_platforms [:macos]

  # Must match the first tier of that environment's runner Price. The
  # default is the real allowance; staging lowers both together so the
  # cap and the paid tier can be reached without burning a hundred
  # minutes of real Mac time to get there. Lowering only this would move
  # the cap without moving the Price, so an account would be cut off
  # before it could ever reach the charged tier.
  @default_free_monthly_minutes 100

  # A projection needs a tenth of the period behind it before it says
  # anything useful.
  @projection_minimum_elapsed_percent 10

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
  def period_breakdown(account, period \\ nil)

  def period_breakdown(%Account{id: account_id} = account, period) do
    # An account on a trial is billed nothing for runner usage, so the
    # breakdown must say so too. Reporting what it would otherwise owe
    # would contradict the bill it is actually going to get.
    on_trial = Trials.on_trial?(account)
    now = DateTime.utc_now()
    {period_start, period_end} = period || billing_window(account, now)
    # A closed period is reported whole; the open one only as far as now.
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    free_ms = free_monthly_minutes() * 60_000

    per_day =
      account_id
      |> RunnerBilling.compute_milliseconds_per_bucket(period_start, usage_end, :day)
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
      period_end: DateTime.to_date(period_end),
      usage_through: DateTime.to_date(usage_end),
      minutes: div(total_ms, 60_000),
      free_minutes: free_monthly_minutes(),
      gross: Prepaid.on_demand_cost_for_milliseconds(total_ms),
      billed:
        if(on_trial,
          do: Money.new(0, :USD),
          else: Prepaid.on_demand_cost_for_milliseconds(max(total_ms - free_ms, 0))
        ),
      days: Enum.reject(days, &(&1.minutes == 0 and &1.gross == Money.new(0, :USD))),
      by_repository: RunnerBilling.compute_milliseconds_per_repository(account_id, period_start, usage_end),
      projected_days: projected_days(total_ms, period_start, period_end, usage_end),
      on_trial: on_trial,
      platforms:
        account_id
        |> platform_rows(period_start, period_end, usage_end, total_ms)
        |> zero_billed_on_trial(on_trial)
    }
  end

  # One row per platform there is a rate for, whether or not it ran.
  # An account has an allowance before it runs anything, and a receipt
  # reading zero says so better than no receipt at all; a platform with
  # no rate has nothing to put on one, so Linux is left off until it is
  # priced. Its minutes still count towards the account's total.
  #
  # Shaped like the usage table it feeds: what the period has used so
  # far, where that lands by the end of it, what the plan covers, and
  # what the period before it came
  # to.
  defp platform_rows(account_id, period_start, period_end, now, total_ms) do
    # The period immediately before this one, the same length, so
    # "previous period" compares like with like whether the window is a
    # subscription cycle or a calendar month.
    previous_end = DateTime.add(period_start, -1, :microsecond)
    previous_start = DateTime.add(period_start, -DateTime.diff(period_end, period_start, :second), :second)

    previous_by_platform = milliseconds_by_platform(account_id, previous_start, previous_end)

    by_platform = milliseconds_by_platform(account_id, period_start, now)

    @priced_platforms
    |> Enum.map(fn platform -> {platform, Map.get(by_platform, platform, 0)} end)
    |> Enum.map(fn {platform, ms} ->
      %{
        id: to_string(platform),
        platform: platform,
        minutes: div(ms, 60_000),
        projected_minutes: project(ms, period_start, period_end, now),
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

  # What each remaining day of an open period would cost if it ran at
  # the rate of the days already in it. Averaged per elapsed day rather
  # than extrapolated from elapsed seconds: on the first day of a period
  # the second-based rate is dominated by the hour that has passed, which
  # produces a figure nobody would recognise.
  defp projected_days(total_ms, period_start, period_end, usage_end) do
    days_elapsed = max(Date.diff(DateTime.to_date(usage_end), DateTime.to_date(period_start)) + 1, 1)
    daily_ms = div(total_ms, days_elapsed)

    first_remaining = usage_end |> DateTime.to_date() |> Date.add(1)
    last = period_end |> DateTime.to_date() |> Date.add(-1)

    if Date.after?(first_remaining, last) or total_ms == 0 do
      []
    else
      first_remaining
      |> Date.range(last)
      |> Enum.map(&%{date: &1, total_ms: daily_ms})
    end
  end

  defp zero_billed_on_trial(rows, false), do: rows

  defp zero_billed_on_trial(rows, true) do
    Enum.map(rows, fn row ->
      %{row | billed: if(is_nil(row.gross), do: nil, else: Money.new(0, :USD))}
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
  # is. Measured against the actual window, so a subscription cycle
  # projects over its own length rather than a calendar month's.
  #
  # Returns nil until enough of the period has passed to extrapolate
  # from. Scaling an hour of a month-long cycle to its full length turns
  # a few hundred minutes into a few hundred thousand, which is not a
  # forecast so much as a division artefact.
  defp project(ms, period_start, period_end, now) do
    elapsed = max(DateTime.diff(now, period_start, :second), 1)
    total = max(DateTime.diff(period_end, period_start, :second), elapsed)

    if elapsed * 100 < total * @projection_minimum_elapsed_percent do
      nil
    else
      ms |> Kernel.*(total) |> div(elapsed) |> div(60_000)
    end
  end

  # Stripe resets a tiered allowance on the subscription cycle, so usage
  # has to be attributed to that same window or the free tier shown here
  # refreshes on a different day from the one the customer is billed
  # against. An account with no subscription has no cycle, and the
  # calendar month is what its allowance follows.
  defp billing_window(account, now) do
    case Billing.current_billing_period(account) do
      {period_start, period_end} -> {period_start, period_end}
      nil -> {beginning_of_month(now), end_of_month(now)}
    end
  end

  defp end_of_month(%DateTime{} = datetime) do
    days = Date.days_in_month(DateTime.to_date(datetime))
    %{datetime | day: days, hour: 23, minute: 59, second: 59, microsecond: {999_999, 6}}
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
