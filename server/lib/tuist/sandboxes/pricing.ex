defmodule Tuist.Sandboxes.Pricing do
  @moduledoc """
  What an account's sandbox usage is worth in a billing period.

  Sandboxes are priced on Tuist Runners' Linux rate card: $0.048 per
  vCPU-hour and $0.006 per GiB-hour of memory, the two parts every Linux
  runner shape's price adds up to (1 vCPU / 2 GB at $0.001 a minute, 2 vCPU /
  8 GB at $0.0024), disk included (`Tuist.Sandboxes.Analytics.compute/2`).
  The same work costs the same in a sandbox as on a runner of its shape.

  Memory is billed max(request, use): every running sandbox its shape's
  memory, which the host keeps for it, and a Linux sandbox also what its VM
  held past that at each report (its process's Pss, less the VMM's 64 MiB).
  A guest cannot pass its shape yet, so the excess stays near zero until
  guests boot larger than their request. A Linux sandbox bursts: it is billed
  CPU, every 30 seconds while it runs, for the larger of what it used and its
  guarantee (`Tuist.Sandboxes.Sandbox.guaranteed_cpu_milli/1`), at least a
  quarter vCPU per GiB of memory, which is the hosts' own ratio (32 vCPUs to
  128 GB). A host filled by sandboxes' memory then earns what one filled by
  runners' CPU does, however little CPU the sandboxes use. A macOS sandbox
  uses its vCPUs for every hour it runs. Paused or archived sandboxes use
  neither.

  Nothing is billed yet: there is no Stripe meter for sandboxes, so the
  whole charge is covered while they are in early access.
  """
  alias Tuist.Billing.UsagePricing
  alias Tuist.Sandboxes.Analytics

  @cents_per_vcpu_hour 4.8
  @cents_per_gib_hour 0.6

  def cents_per_vcpu_hour, do: @cents_per_vcpu_hour
  def cents_per_gib_hour, do: @cents_per_gib_hour

  @doc """
  The period's vCPU-hours and memory GiB-hours and their value per day,
  where the period lands at its rate so far, how much the previous period
  came to, and what is billed.
  """
  def period_breakdown(account_id, {%DateTime{} = period_start, %DateTime{} = period_end}) do
    now = DateTime.utc_now()
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    usage = vcpu_usage(account_id, period_start, usage_end)
    previous = vcpu_usage(account_id, Timex.shift(period_start, months: -1), period_start)
    cpu = cents(usage.vcpu_hours, @cents_per_vcpu_hour)
    memory = cents(usage.memory_gib_hours, @cents_per_gib_hour)
    gross = Money.add(cpu, memory)

    days =
      [usage.dates, usage.values, usage.memory_values]
      |> Enum.zip()
      |> Enum.map(fn {date, vcpu_hours, gib_hours} ->
        %{date: date, dollars: (vcpu_hours * @cents_per_vcpu_hour + gib_hours * @cents_per_gib_hour) / 100}
      end)
      |> Enum.reject(&(&1.dollars == 0))

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      vcpu_hours: usage.vcpu_hours,
      memory_gib_hours: usage.memory_gib_hours,
      previous_vcpu_hours: previous.vcpu_hours,
      projected_vcpu_hours: UsagePricing.project(round(usage.vcpu_hours), period_start, period_end, usage_end),
      cpu: cpu,
      memory: memory,
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

  defp cents(hours, rate), do: Money.new(round(hours * rate), :USD)
end
