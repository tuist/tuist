defmodule Tuist.Runners.Allowance do
  @moduledoc """
  The free monthly runner allowance, and whether an account may keep
  dispatching once it is spent.

  Every plan gets the same allowance, because it is a tier on the macOS
  runner Price rather than a plan attribute: the first
  `free_monthly_minutes/0` macOS baseline machine-minutes of each
  billing period cost nothing, and usage past that is charged at the
  standard rate. Linux has no free tier: its Price charges from the
  first minute. What differs by plan is whether exceeding the allowance
  is *possible*.

  A paid plan can exceed it and be billed for the excess. A free account
  cannot: it has no subscription for the excess to land on, so without a
  cap its runner usage would be unbounded and unbillable. That is the
  one thing this module enforces.

  ## Why the cap is here and not in the Price

  Stripe can express the free tier but not refuse the work. The Price
  stops charging below the allowance; only dispatch can stop a job from
  running past it. The two have to agree, so
  `free_monthly_minutes/0` and the macOS Price's first tier are the same
  number stated twice, and have to be changed together — the same
  hand-kept duplication `Tuist.Billing`'s `@unit_prices` carries.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Billing, as: RunnerBilling
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.Trials

  @priced_platforms [:macos, :linux]

  # The one platform whose Price has a free first tier.
  @allowance_platform :macos

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

  Every platform counts, although only macOS has a free tier. An account
  with no subscription has nothing to bill Linux time against either, so
  its Linux time spends the same cap rather than running unbounded.
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

    per_day =
      account_id
      |> per_day_by_platform(period_start, usage_end)
      |> Enum.sort_by(fn {date, _by_platform} -> Date.to_erl(date) end)

    covered_per_day = covered_per_day(account_id, trial_window)

    {days, _remaining} =
      Enum.map_reduce(per_day, free_ms, fn {date, by_platform}, remaining_free ->
        # The allowance is spent by billable usage only. Letting a day
        # the trial covered consume it would charge the account for
        # minutes the trial was supposed to pay for, one day later.
        billable = subtract(by_platform, Map.get(covered_per_day, date, %{}))
        included = min(Map.get(billable, @allowance_platform, 0), remaining_free)

        day = %{
          # The table keys rows on `:id`; without one every row shares a
          # DOM id and LiveView cannot patch the list.
          id: Date.to_iso8601(date),
          date: date,
          minutes: div(sum(by_platform), 60_000),
          gross: cost(by_platform),
          billed: cost(Map.update(billable, @allowance_platform, 0, &(&1 - included)))
        }

        {day, remaining_free - included}
      end)

    priced = per_day |> Enum.map(&elem(&1, 1)) |> merge()
    covered = covered_per_day |> Map.values() |> merge()
    billable = subtract(priced, covered)

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      usage_through: DateTime.to_date(usage_end),
      minutes: div(sum(priced), 60_000),
      free_minutes: free_monthly_minutes(),
      gross: cost(priced),
      trial_covered: cost(covered),
      billed: cost(Map.update(billable, @allowance_platform, 0, &max(&1 - free_ms, 0))),
      days: Enum.reject(days, &(&1.minutes == 0 and &1.gross == Money.new(0, :USD))),
      by_repository: by_repository(account_id, period_start, usage_end),
      projected_days: projected_days(priced, period_start, period_end, usage_end),
      platforms: platform_rows(account_id, period_start, period_end, usage_end, trial_window)
    }
  end

  # `%{date => %{platform => ms}}`, one query per platform because each
  # platform's compute units are priced at its own rate and cannot be
  # summed into one figure before they are costed.
  defp per_day_by_platform(account_id, from, to) do
    for platform <- @priced_platforms,
        {date, ms} <- RunnerBilling.compute_milliseconds_per_bucket(account_id, from, to, :day, platforms: [platform]),
        reduce: %{} do
      acc -> Map.update(acc, date, %{platform => ms}, &Map.put(&1, platform, ms))
    end
  end

  # Per day, repository and platform, so the chart can value each row at
  # its own platform's rate.
  defp by_repository(account_id, from, to) do
    @priced_platforms
    |> Enum.flat_map(fn platform ->
      account_id
      |> RunnerBilling.compute_milliseconds_per_repository(from, to, platforms: [platform])
      |> Enum.map(&Map.put(&1, :platform, platform))
    end)
    |> Enum.sort_by(&{Date.to_erl(&1.date), &1.repository, &1.platform})
  end

  defp merge(by_platform_maps),
    do: Enum.reduce(by_platform_maps, %{}, &Map.merge(&2, &1, fn _platform, a, b -> a + b end))

  defp subtract(by_platform, covered),
    do: Map.new(by_platform, fn {platform, ms} -> {platform, ms - Map.get(covered, platform, 0)} end)

  defp sum(by_platform), do: by_platform |> Map.values() |> Enum.sum()

  defp cost(by_platform) do
    Enum.reduce(by_platform, Money.new(0, :USD), fn {platform, ms}, total ->
      Money.add(total, Prepaid.on_demand_cost_for_milliseconds(platform, ms))
    end)
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

  defp covered_per_day(account_id, {from, to}), do: per_day_by_platform(account_id, from, to)

  # True when a trial covered the period end to end, and so the account
  # cannot reach its allowance anywhere in it.
  defp fully_covered?(nil, _period_start, _usage_end), do: false

  defp fully_covered?({from, to}, period_start, usage_end) do
    not DateTime.after?(from, period_start) and not DateTime.before?(to, usage_end)
  end

  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

  # One row per platform, whether or not it ran. An account has an
  # allowance before it runs anything, and a receipt reading zero says so
  # better than no receipt at all.
  #
  # Shaped like the usage table it feeds: what the period has used so
  # far, where that lands by the end of it, what the plan covers, and
  # what the period before it came to.
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

    Enum.map(@priced_platforms, fn platform ->
      ms = Map.get(by_platform, platform, 0)
      billable_ms = ms - Map.get(covered_by_platform, platform, 0)

      %{
        id: to_string(platform),
        platform: platform,
        minutes: div(ms, 60_000),
        projected_minutes: project(ms, period_start, period_end, usage_end),
        # Only the macOS Price has a free tier. An account with nothing
        # billable in the period cannot reach it at all, and a line it
        # can never spend is worse than no line.
        included_minutes: if(platform == @allowance_platform and reachable_allowance?, do: free_monthly_minutes()),
        previous_minutes: previous_by_platform |> Map.get(platform, 0) |> div(60_000),
        gross: Prepaid.on_demand_cost_for_milliseconds(platform, ms),
        trial_covered: Prepaid.on_demand_cost_for_milliseconds(platform, ms - billable_ms),
        billed: Prepaid.on_demand_cost_for_milliseconds(platform, billed_milliseconds(platform, billable_ms))
      }
    end)
  end

  # What each remaining day of an open period would cost if it ran at
  # the rate of the days already in it, one row per platform so each is
  # valued at its own rate. Averaged per elapsed day rather than
  # extrapolated from elapsed seconds: on the first day of a period the
  # second-based rate is dominated by the hour that has passed, which
  # produces a figure nobody would recognise.
  defp projected_days(by_platform, period_start, period_end, usage_end) do
    days_elapsed = max(Date.diff(DateTime.to_date(usage_end), DateTime.to_date(period_start)) + 1, 1)

    first_remaining = usage_end |> DateTime.to_date() |> Date.add(1)
    last = period_end |> DateTime.to_date() |> Date.add(-1)

    if Date.after?(first_remaining, last) do
      []
    else
      for date <- Date.range(first_remaining, last),
          {platform, ms} <- Enum.sort(by_platform),
          ms > 0,
          do: %{date: date, platform: platform, total_ms: div(ms, days_elapsed)}
    end
  end

  defp covered_by_platform(_account_id, nil), do: %{}

  defp covered_by_platform(account_id, {from, to}), do: milliseconds_by_platform(account_id, from, to)

  # Compute units rather than elapsed time, so a receipt costs a larger
  # machine at the multiple Stripe is metered on.
  defp milliseconds_by_platform(account_id, period_start, period_end) do
    account_id
    |> RunnerBilling.compute_units_by_platform(period_start, period_end)
    |> Map.new(&{&1.platform, &1.total_units})
  end

  defp billed_milliseconds(@allowance_platform, billable_ms), do: max(billable_ms - free_monthly_minutes() * 60_000, 0)

  defp billed_milliseconds(_platform, billable_ms), do: billable_ms

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
