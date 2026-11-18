defmodule Tuist.Sandboxes.Pricing do
  @moduledoc """
  What an account's sandbox usage is worth in a billing period.

  Sandboxes are priced per vCPU-hour, memory and disk included: a running
  sandbox uses its vCPUs for every hour it runs, and paused or archived
  ones use none. The rate sits below Tuist Runners' Linux rate ($0.072 per
  vCPU-hour on the 2 vCPU / 8 GB baseline) and below E2B and Daytona, which
  charge $0.0504 per vCPU-hour plus memory, about $0.08 for the 2 GB per
  vCPU our shapes have.

  Nothing is billed yet: there is no Stripe meter for sandboxes, so the
  whole charge is covered while they are in early access.
  """
  alias Tuist.Billing.UsagePricing
  alias Tuist.Sandboxes.Analytics

  @cents_per_vcpu_hour 6

  def cents_per_vcpu_hour, do: @cents_per_vcpu_hour

  @doc """
  The period's vCPU-hours and their value per day, where the period lands
  at its rate so far, how much the previous period came to, and what is
  billed.
  """
  def period_breakdown(account_id, {%DateTime{} = period_start, %DateTime{} = period_end}) do
    now = DateTime.utc_now()
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    usage = vcpu_usage(account_id, period_start, usage_end)
    previous = vcpu_usage(account_id, Timex.shift(period_start, months: -1), period_start)
    gross = cost(usage.vcpu_hours)

    days =
      usage.dates
      |> Enum.zip(usage.values)
      |> Enum.reject(fn {_date, vcpu_hours} -> vcpu_hours == 0 end)
      |> Enum.map(fn {date, vcpu_hours} -> %{date: date, dollars: vcpu_hours * @cents_per_vcpu_hour / 100} end)

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      vcpu_hours: usage.vcpu_hours,
      previous_vcpu_hours: previous.vcpu_hours,
      projected_vcpu_hours: UsagePricing.project(round(usage.vcpu_hours), period_start, period_end, usage_end),
      gross: gross,
      early_access_credit: gross,
      billed: Money.new(0, :USD),
      days: days,
      projected_days:
        UsagePricing.projected_days(
          %{dollars: days |> Enum.map(& &1.dollars) |> Enum.sum()},
          period_start,
          period_end,
          usage_end
        )
    }
  end

  # A window ends where the next starts, so its last instant, which
  # `Analytics.compute/2` counts, is a second before.
  defp vcpu_usage(account_id, from, to) do
    Analytics.compute(account_id, start_datetime: from, end_datetime: DateTime.add(to, -1, :second))
  end

  defp cost(vcpu_hours), do: Money.new(round(vcpu_hours * @cents_per_vcpu_hour), :USD)
end
