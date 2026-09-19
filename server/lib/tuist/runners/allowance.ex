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
    cond do
      # A runner trial is precisely "uses runners without being billed for
      # them", so the free-tier cut-off cannot apply to it. A trial account has
      # no subscription, so `effective_plan/1` reports `:air` and it would
      # otherwise be cut off at the baseline — leaving the account on a trial
      # that does not let it run runners. The trial is what makes the usage
      # unbillable; nothing else has to hold it back.
      Trials.on_trial?(account) -> false
      Billing.effective_plan(account) == :air -> minutes_used(account) >= free_monthly_minutes()
      true -> false
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

  Usage a runner trial covered is reported and valued but never priced,
  and never spends the allowance either. `trial_covered` is what the
  trial took off, so a period the trial ended part-way through reads as
  minutes run, less what the trial covered, less what the plan includes,
  leaving what is billed.
  """
  def period_breakdown(account, period \\ nil)

  def period_breakdown(%Account{id: account_id} = account, period) do
    now = DateTime.utc_now()
    {period_start, period_end} = period || billing_window(account, now)
    # A closed period is reported whole; the open one only as far as now.
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    trial_window = trial_window(account, period_start, usage_end)
    free_ms = free_monthly_minutes() * 60_000

    # Money is only ever put on usage there is a rate for. Linux runs
    # are reported but cannot be invoiced, so pricing them at the macOS
    # rate would show an account a bill no invoice can carry.
    per_day =
      account_id
      |> RunnerBilling.compute_milliseconds_per_bucket(period_start, usage_end, :day, platforms: @priced_platforms)
      |> Enum.sort_by(fn {date, _ms} -> Date.to_erl(date) end)

    covered_per_day = covered_per_day(account_id, trial_window)

    {days, _remaining} =
      Enum.map_reduce(per_day, free_ms, fn {date, ms}, remaining_free ->
        # The allowance is spent by billable usage only. Letting a day
        # the trial covered consume it would charge the account for
        # minutes the trial was supposed to pay for, one day later.
        priced = ms - Map.get(covered_per_day, date, 0)
        covered = min(priced, remaining_free)
        billable = priced - covered

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

    priced_ms = per_day |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    covered_ms = covered_per_day |> Map.values() |> Enum.sum()

    # Every minute the account ran, priced or not: it did use them, and
    # the minute count is what it is judged against.
    total_ms = RunnerBilling.compute_milliseconds(account_id, period_start, usage_end)

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      usage_through: DateTime.to_date(usage_end),
      minutes: div(total_ms, 60_000),
      free_minutes: free_monthly_minutes(),
      gross: Prepaid.on_demand_cost_for_milliseconds(priced_ms),
      trial_covered: Prepaid.on_demand_cost_for_milliseconds(covered_ms),
      billed: Prepaid.on_demand_cost_for_milliseconds(max(priced_ms - covered_ms - free_ms, 0)),
      days: Enum.reject(days, &(&1.minutes == 0 and &1.gross == Money.new(0, :USD))),
      by_repository:
        RunnerBilling.compute_milliseconds_per_repository(account_id, period_start, usage_end,
          platforms: @priced_platforms
        ),
      projected_days: projected_days(priced_ms, period_start, period_end, usage_end),
      platforms: platform_rows(account_id, period_start, period_end, usage_end, trial_window)
    }
  end

  # The slice of `[period_start, usage_end]` a runner trial covered, or
  # `nil` when it covered none of it.
  #
  # A trial is the absence of a runner item on the subscription, so the
  # usage it covered has nothing to be invoiced against, and ending one
  # adds the item with `proration_behavior: "none"` so Stripe bills from
  # that instant on. What the trial covers is therefore an interval, and
  # a period is covered only where it overlaps that interval: usage that
  # ran before the trial started was billable, and so is usage after it
  # ended. The page offers a year of history, so a period that closed
  # before the trial began has to keep reading as fully billable.
  #
  # A restarted trial overwrites both timestamps, so a period covered by
  # an earlier trial reads as billable. Reconstructing that needs a
  # record of every transition rather than of the latest one. It is only
  # ever a display inaccuracy: an account carries no runner item while a
  # trial runs, so it was not invoiced for those minutes either.
  defp trial_window(%Account{runner_trial_started_at: nil}, _period_start, _usage_end), do: nil

  defp trial_window(%Account{} = account, period_start, usage_end) do
    from = latest(account.runner_trial_started_at, period_start)
    to = earliest(account.runner_trial_ended_at || usage_end, usage_end)

    if DateTime.before?(from, to), do: {from, to}
  end

  # Per-day milliseconds a trial covered. Measured rather than sliced out
  # of the period's own buckets, because a trial can start or end
  # part-way through a day and only the query knows how much of that
  # day's runs fell on each side.
  defp covered_per_day(_account_id, nil), do: %{}

  defp covered_per_day(account_id, {from, to}) do
    RunnerBilling.compute_milliseconds_per_bucket(account_id, from, to, :day, platforms: @priced_platforms)
  end

  # True when a trial covered the period end to end, and so the account
  # cannot reach its allowance anywhere in it.
  defp fully_covered?(nil, _period_start, _usage_end), do: false

  defp fully_covered?({from, to}, period_start, usage_end) do
    not DateTime.after?(from, period_start) and not DateTime.before?(to, usage_end)
  end

  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

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
  defp platform_rows(account_id, period_start, period_end, usage_end, trial_window) do
    # The period immediately before this one, the same length, so
    # "previous period" compares like with like whether the window is a
    # subscription cycle or a calendar month.
    previous_end = DateTime.add(period_start, -1, :microsecond)
    previous_start = DateTime.add(period_start, -DateTime.diff(period_end, period_start, :second), :second)

    previous_by_platform = milliseconds_by_platform(account_id, previous_start, previous_end)

    by_platform = milliseconds_by_platform(account_id, period_start, usage_end)

    covered_by_platform = covered_by_platform(account_id, trial_window)
    reachable_allowance? = not fully_covered?(trial_window, period_start, usage_end)

    billable_total_ms =
      @priced_platforms
      |> Enum.map(&(Map.get(by_platform, &1, 0) - Map.get(covered_by_platform, &1, 0)))
      |> Enum.sum()

    Enum.map(@priced_platforms, fn platform ->
      ms = Map.get(by_platform, platform, 0)
      billable_ms = ms - Map.get(covered_by_platform, platform, 0)

      %{
        id: to_string(platform),
        platform: platform,
        minutes: div(ms, 60_000),
        projected_minutes: project(ms, period_start, period_end, usage_end),
        # The allowance is one pot for the account rather than one per
        # platform, so it is only meaningful against a platform that has
        # a rate to spend it at. macOS is the only one so far. An
        # account with nothing billable in the period cannot reach it at
        # all, and a line it can never spend is worse than no line.
        included_minutes: if(platform == :macos and reachable_allowance?, do: free_monthly_minutes()),
        previous_minutes: previous_by_platform |> Map.get(platform, 0) |> div(60_000),
        gross: platform_cost(platform, ms),
        trial_covered: platform_cost(platform, ms - billable_ms),
        billed: platform_cost(platform, billable_milliseconds(billable_ms, billable_total_ms))
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

  defp covered_by_platform(_account_id, nil), do: %{}

  defp covered_by_platform(account_id, {from, to}), do: milliseconds_by_platform(account_id, from, to)

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
  # free milliseconds are taken off the period's billable total.
  defp billable_milliseconds(ms, total_ms) do
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
