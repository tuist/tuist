defmodule Tuist.Billing.UsagePricing do
  @moduledoc """
  Usage-based pricing for cache traffic and test insights.

  Downloads and requests from every cache share one allowance per billing
  period, and traffic served from a Tuist Runners cache region counts at half.
  Passing test cases are billed, while failed and skipped ones and anything run
  on Tuist Runners are free.

  The allowances and rates must match the first tier and unit price of the
  Prices in `stripe.prices.usage_meters`.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.UsageMeters

  @egress_meter "cache_egress_megabytes"
  @request_meter "cache_requests"
  @passing_test_case_meter "passing_test_cases"

  @included_egress_bytes 100_000_000_000
  @included_requests 1_000_000
  @included_passing_test_cases 5_000_000

  @cents_per_egress_gigabyte 35
  @cents_per_thousand_requests 1
  @cents_per_million_passing_test_cases 200

  @bytes_per_gigabyte 1_000_000_000
  @bytes_per_megabyte 1_000_000

  @projection_minimum_elapsed_percent 10

  def included_egress_bytes, do: @included_egress_bytes
  def included_requests, do: @included_requests
  def included_passing_test_cases, do: @included_passing_test_cases

  @doc """
  The values reported to Stripe for `[period_start, period_end)`. Runner
  traffic is halved before reporting, so the shared allowance applies to what
  is left.
  """
  def meter_values(%Account{id: account_id}, %DateTime{} = period_start, %DateTime{} = period_end) do
    cache = account_id |> UsageMeters.cache_downloads(period_start, period_end) |> cache_totals()
    tests = account_id |> UsageMeters.test_case_runs(period_start, period_end) |> test_totals()

    [
      %{event_name: @egress_meter, value: div(metered(cache.bytes, cache.runner_bytes), @bytes_per_megabyte)},
      %{event_name: @request_meter, value: metered(cache.requests, cache.runner_requests)},
      %{event_name: @passing_test_case_meter, value: tests.passed}
    ]
  end

  @doc """
  The period's cache and test insights usage, what it is worth, and what the
  allowances take off it. `billed` is only set for an account with a
  subscription to bill against.
  """
  def period_breakdown(%Account{} = account, {%DateTime{} = period_start, %DateTime{} = period_end}) do
    now = DateTime.utc_now()
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    subscribed = not is_nil(Billing.get_current_active_subscription(account))

    cache_rows = UsageMeters.cache_downloads(account.id, period_start, usage_end)
    test_rows = UsageMeters.test_case_runs(account.id, period_start, usage_end)
    project_names = UsageMeters.project_names(account.id)
    period = {period_start, period_end, usage_end}

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      usage_through: DateTime.to_date(usage_end),
      cache: cache_breakdown(cache_rows, project_names, subscribed, period),
      tests: tests_breakdown(test_rows, project_names, subscribed, period)
    }
  end

  defp cache_breakdown(rows, project_names, subscribed, {period_start, period_end, usage_end}) do
    totals = cache_totals(rows)

    egress =
      totals.bytes
      |> receipt(totals.runner_bytes, @included_egress_bytes, &egress_cost/1)
      |> Map.put(:projected, project(totals.bytes, period_start, period_end, usage_end))

    requests =
      totals.requests
      |> receipt(totals.runner_requests, @included_requests, &request_cost/1)
      |> Map.put(:projected, project(totals.requests, period_start, period_end, usage_end))

    charge = Money.add(egress.charge, requests.charge)
    charge_days = charge_days(rows)

    %{
      egress: egress,
      requests: requests,
      gross: Money.add(egress.gross, requests.gross),
      charge: charge,
      billed: if(subscribed, do: charge),
      days: cache_days(rows, project_names),
      charge_days: charge_days,
      projected_days:
        projected_days(
          %{bytes: totals.bytes, requests: totals.requests, dollars: charge_days |> Enum.map(& &1.dollars) |> Enum.sum()},
          period_start,
          period_end,
          usage_end
        )
    }
  end

  defp tests_breakdown(rows, project_names, subscribed, {period_start, period_end, usage_end}) do
    totals = test_totals(rows)
    billable = max(totals.passed - @included_passing_test_cases, 0)
    gross = passing_test_case_cost(totals.passed)
    charge = passing_test_case_cost(billable)

    days =
      rows
      |> Enum.filter(&(&1.status == "success" and not &1.runners))
      |> Enum.group_by(&{&1.date, Map.get(project_names, &1.project_id)}, & &1.count)
      |> Enum.map(fn {{date, project}, counts} ->
        %{
          date: date,
          project: project,
          dollars: dollars(Enum.sum(counts) * @cents_per_million_passing_test_cases / 1_000_000)
        }
      end)
      |> Enum.sort_by(&{Date.to_erl(&1.date), &1.project || ""})

    Map.merge(totals, %{
      included: @included_passing_test_cases,
      billable: billable,
      projected: project(totals.passed, period_start, period_end, usage_end),
      gross: gross,
      included_credit: Money.subtract(gross, charge),
      charge: charge,
      billed: if(subscribed, do: charge),
      days: days,
      projected_days:
        projected_days(%{dollars: days |> Enum.map(& &1.dollars) |> Enum.sum()}, period_start, period_end, usage_end)
    })
  end

  defp receipt(quantity, runner_quantity, included, cost) do
    metered = metered(quantity, runner_quantity)
    billable = max(metered - included, 0)
    gross = cost.(quantity)

    %{
      quantity: quantity,
      runner_quantity: runner_quantity,
      metered: metered,
      included: included,
      billable: billable,
      gross: gross,
      runner_credit: Money.subtract(gross, cost.(metered)),
      included_credit: Money.subtract(cost.(metered), cost.(billable)),
      charge: cost.(billable)
    }
  end

  defp cache_days(rows, project_names) do
    rows
    |> Enum.group_by(&{&1.date, Map.get(project_names, &1.project_id)})
    |> Enum.map(fn {{date, project}, project_rows} ->
      %{
        date: date,
        project: project,
        bytes: project_rows |> Enum.map(& &1.bytes) |> Enum.sum(),
        requests: project_rows |> Enum.map(& &1.requests) |> Enum.sum()
      }
    end)
    |> Enum.sort_by(&{Date.to_erl(&1.date), &1.project || ""})
  end

  defp charge_days(rows) do
    rows
    |> Enum.flat_map(fn row ->
      share = if row.runners, do: 0.5, else: 1

      [
        %{
          date: row.date,
          meter: :egress,
          dollars: dollars(row.bytes * share * @cents_per_egress_gigabyte / @bytes_per_gigabyte)
        },
        %{date: row.date, meter: :requests, dollars: dollars(row.requests * share * @cents_per_thousand_requests / 1_000)}
      ]
    end)
    |> Enum.group_by(&{&1.date, &1.meter}, & &1.dollars)
    |> Enum.map(fn {{date, meter}, dollars} -> %{date: date, meter: meter, dollars: Enum.sum(dollars)} end)
    |> Enum.sort_by(&{Date.to_erl(&1.date), &1.meter})
  end

  defp projected_days(totals, period_start, period_end, usage_end) do
    days_elapsed = max(Date.diff(DateTime.to_date(usage_end), DateTime.to_date(period_start)) + 1, 1)
    first_remaining = usage_end |> DateTime.to_date() |> Date.add(1)
    last = period_end |> DateTime.add(-1, :microsecond) |> DateTime.to_date()
    daily = Map.new(totals, fn {key, total} -> {key, total / days_elapsed} end)

    if Enum.all?(Map.values(totals), &(&1 == 0)) or Date.after?(first_remaining, last) do
      []
    else
      first_remaining
      |> Date.range(last)
      |> Enum.map(&Map.put(daily, :date, &1))
    end
  end

  defp project(quantity, period_start, period_end, usage_end) do
    elapsed = max(DateTime.diff(usage_end, period_start, :second), 1)
    total = max(DateTime.diff(period_end, period_start, :second), elapsed)

    if elapsed * 100 >= total * @projection_minimum_elapsed_percent do
      div(quantity * total, elapsed)
    end
  end

  defp cache_totals(rows) do
    Enum.reduce(rows, %{bytes: 0, requests: 0, runner_bytes: 0, runner_requests: 0}, fn row, totals ->
      totals = %{totals | bytes: totals.bytes + row.bytes, requests: totals.requests + row.requests}

      if row.runners do
        %{totals | runner_bytes: totals.runner_bytes + row.bytes, runner_requests: totals.runner_requests + row.requests}
      else
        totals
      end
    end)
  end

  defp test_totals(rows) do
    Enum.reduce(rows, %{passed: 0, failed: 0, skipped: 0, on_runners: 0}, fn
      %{runners: true, count: count}, totals -> %{totals | on_runners: totals.on_runners + count}
      %{status: "success", count: count}, totals -> %{totals | passed: totals.passed + count}
      %{status: "failure", count: count}, totals -> %{totals | failed: totals.failed + count}
      %{status: "skipped", count: count}, totals -> %{totals | skipped: totals.skipped + count}
    end)
  end

  defp metered(quantity, runner_quantity), do: quantity - runner_quantity + div(runner_quantity, 2)

  defp egress_cost(bytes), do: Money.new(div(bytes * @cents_per_egress_gigabyte, @bytes_per_gigabyte), :USD)

  defp request_cost(requests), do: Money.new(div(requests * @cents_per_thousand_requests, 1_000), :USD)

  defp passing_test_case_cost(count), do: Money.new(div(count * @cents_per_million_passing_test_cases, 1_000_000), :USD)

  defp dollars(cents), do: cents / 100
end
