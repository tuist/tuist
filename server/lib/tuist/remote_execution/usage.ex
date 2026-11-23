defmodule Tuist.RemoteExecution.Usage do
  @moduledoc """
  Remote execution usage and what it is worth.

  Each single-use VM that runs an action records how long the node measured
  the executor running in it (`Tuist.RemoteExecution.UsageEvent`), for both
  scheduled and leased executions. That time starts when the executor starts
  and ends when it exits, so it includes fetching inputs and uploading
  outputs, but never queueing, booting or preparing the VM. Every action is
  counted to the millisecond, with no per-action minimum.

  The time is priced at the Linux runner rate for the VM's shape: it is
  weighted by `Tuist.Runners.Catalog.billing_multiplier/3` and costed with
  `Tuist.Runners.Prepaid.on_demand_dollars/2`, rounded to the nearest cent, so 2 vCPU / 4 GB
  costs $0.002, 4 vCPU / 8 GB $0.004 and 8 vCPU / 16 GB $0.008 a minute, as
  the pricing page lists.

  It is billed on the Linux runner meter rather than a meter of its own: the
  same compute-unit milliseconds, added to the runner time each report
  carries (`metered_units_by_platform/3`). It therefore shares that Price's
  free monthly minutes, prepaid credit grants and runner trials, and appears
  on the invoice as Linux compute. `Tuist.Runners.Allowance.remote_execution_billed/3`
  splits the meter's charge back out for the usage page.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing.UsageMeters
  alias Tuist.Billing.UsagePricing
  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseTimeSeries
  alias Tuist.RemoteExecution.UsageEvent
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Billing, as: RunnerBilling
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Prepaid
  alias Tuist.Sandboxes.Sandbox

  @doc """
  Records the action a VM ran for `project_id`, when the node reported how
  long the executor ran. Older nodes that report no duration record nothing.
  """
  def record(%Sandbox{} = sandbox, project_id, mode, %{"duration_ms" => duration_ms})
      when mode in ["scheduled", "leased"] and is_integer(duration_ms) and duration_ms >= 0 do
    UsageEvent.Buffer.insert(%{
      id: UUIDv7.generate(),
      account_id: sandbox.account_id,
      project_id: project_id,
      sandbox_id: sandbox.id,
      mode: mode,
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      duration_ms: duration_ms,
      inserted_at: NaiveDateTime.utc_now()
    })

    :ok
  end

  def record(_sandbox, _project_id, _mode, _result), do: :ok

  @doc """
  The period's execution time per shape, its value per day, where the period
  lands at its rate so far, how much the previous period came to, and what
  is billed.
  """
  def period_breakdown(%Account{id: account_id} = account, {%DateTime{} = period_start, %DateTime{} = period_end}) do
    now = DateTime.utc_now()
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    rows = usage(account_id, period_start, usage_end)
    previous = usage(account_id, Timex.shift(period_start, months: -1), period_start)
    project_names = UsageMeters.project_names(account_id)

    shapes =
      rows
      |> Enum.group_by(&{&1.vcpus, &1.memory_gb})
      |> Enum.map(fn {{vcpus, memory_gb}, shape_rows} ->
        ms = shape_rows |> Enum.map(& &1.duration_ms) |> Enum.sum()

        %{
          vcpus: vcpus,
          memory_gb: memory_gb,
          actions: shape_rows |> Enum.map(& &1.actions) |> Enum.sum(),
          minutes: ms / 60_000,
          gross: cost(compute_unit_ms(ms, vcpus, memory_gb))
        }
      end)
      |> Enum.sort_by(&{&1.vcpus, &1.memory_gb})

    gross = rows |> Enum.map(&row_units/1) |> Enum.sum() |> cost()

    days =
      rows
      |> Enum.group_by(&{&1.date, Map.get(project_names, &1.project_id)})
      |> Enum.map(fn {{date, project}, day_rows} ->
        %{
          date: date,
          project: project,
          dollars: Prepaid.on_demand_dollars(:linux, day_rows |> Enum.map(&row_units/1) |> Enum.sum())
        }
      end)
      |> Enum.sort_by(& &1.date, Date)

    minutes = rows |> Enum.map(& &1.duration_ms) |> Enum.sum() |> Kernel./(60_000)

    %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      actions: rows |> Enum.map(& &1.actions) |> Enum.sum(),
      minutes: minutes,
      previous_minutes: previous |> Enum.map(& &1.duration_ms) |> Enum.sum() |> Kernel./(60_000),
      projected_minutes: UsagePricing.project(round(minutes), period_start, period_end, usage_end),
      shapes: shapes,
      gross: gross,
      billed: account |> Allowance.remote_execution_billed(period_start, usage_end) |> at_most(gross),
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

  @doc """
  What `project` ran in `[from, to)`: executions and their measured time in
  total, per VM shape, per dispatch mode, and per hour, day or month bucket
  as the dashboard analytics use. Every bucket of the period is present;
  buckets without executions are zero, since the ledger records every
  execution a node measured.
  """
  def project_usage(%{id: project_id, account_id: account_id}, %DateTime{} = from, %DateTime{} = to) do
    granularity = ClickHouseTimeSeries.granularity(from, DateTime.add(to, -1))
    date_format = ClickHouseTimeSeries.date_format(granularity)

    rows =
      from(e in UsageEvent,
        where: e.account_id == ^account_id and e.project_id == ^project_id,
        where: e.inserted_at >= ^DateTime.to_naive(from) and e.inserted_at < ^DateTime.to_naive(to),
        group_by: [fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format), e.vcpus, e.memory_mb, e.mode],
        select: %{
          date: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format),
          vcpus: e.vcpus,
          memory_gb: fragment("intDiv(?, 1024)", e.memory_mb),
          mode: e.mode,
          execution_ms: fragment("sum(?)", e.duration_ms),
          executions: fragment("count()")
        }
      )
      |> ClickHouseRepo.all()
      |> Enum.map(&%{&1 | execution_ms: to_integer(&1.execution_ms), executions: to_integer(&1.executions)})

    dates = ClickHouseTimeSeries.buckets(from, DateTime.add(to, -1), granularity)

    shapes =
      rows
      |> Enum.group_by(&{&1.vcpus, &1.memory_gb})
      |> Enum.sort()
      |> Enum.map(fn {{vcpus, memory_gb}, shape_rows} ->
        by_date = Enum.group_by(shape_rows, & &1.date)

        Map.merge(totals(shape_rows), %{
          vcpus: vcpus,
          memory_gb: memory_gb,
          series: Enum.map(dates, &totals(Map.get(by_date, &1, [])))
        })
      end)

    by_date = Enum.group_by(rows, & &1.date)

    Map.merge(totals(rows), %{
      shapes: shapes,
      modes:
        rows
        |> Enum.group_by(& &1.mode)
        |> Enum.sort()
        |> Enum.map(fn {mode, mode_rows} -> Map.put(totals(mode_rows), :mode, mode) end),
      granularity: granularity,
      dates: dates,
      series: Enum.map(dates, &totals(Map.get(by_date, &1, [])))
    })
  end

  defp totals(rows) do
    %{
      executions: rows |> Enum.map(& &1.executions) |> Enum.sum(),
      execution_ms: rows |> Enum.map(& &1.execution_ms) |> Enum.sum()
    }
  end

  @doc """
  Linux compute-unit milliseconds of remote execution `account_id` ran in
  `[from, to)`, the unit the Linux runner meter is reported in.
  """
  def compute_units(account_id, %DateTime{} = from, %DateTime{} = to) do
    account_id |> usage(from, to) |> Enum.map(&row_units/1) |> Enum.sum()
  end

  @doc """
  What each runner meter carries for `account_id` over the window: runner
  compute units by platform (`Tuist.Runners.Billing.compute_units_by_platform/3`),
  with remote execution added to Linux. Use it wherever a figure has to agree
  with what Stripe charges, such as reporting, the free allowance and prepaid
  credit; runner-only views keep reading `Tuist.Runners.Billing`.
  """
  def metered_units_by_platform(account_id, %DateTime{} = from, %DateTime{} = to) do
    by_platform = RunnerBilling.compute_units_by_platform(account_id, from, to)

    case compute_units(account_id, from, to) do
      0 ->
        by_platform

      units ->
        if Enum.any?(by_platform, &(&1.platform == :linux)) do
          Enum.map(by_platform, fn
            %{platform: :linux} = usage -> %{usage | total_units: usage.total_units + units}
            usage -> usage
          end)
        else
          Enum.sort_by([%{platform: :linux, total_units: units} | by_platform], & &1.platform)
        end
    end
  end

  @doc "The VM memory sizes, in GB, that ran an action of `account_id` since `since`."
  def memory_sizes_gb(account_id, %DateTime{} = since) do
    from(e in UsageEvent,
      where: e.account_id == ^account_id and e.inserted_at >= ^DateTime.to_naive(since),
      distinct: true,
      select: e.memory_mb
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&div(&1, 1024))
  end

  defp usage(account_id, from, to) do
    from(e in UsageEvent,
      where: e.account_id == ^account_id,
      where: e.inserted_at >= ^DateTime.to_naive(from) and e.inserted_at < ^DateTime.to_naive(to),
      group_by: [fragment("toDate(?)", e.inserted_at), e.project_id, e.vcpus, e.memory_mb],
      select: %{
        date: fragment("toDate(?)", e.inserted_at),
        project_id: e.project_id,
        vcpus: e.vcpus,
        memory_mb: e.memory_mb,
        duration_ms: fragment("sum(?)", e.duration_ms),
        actions: fragment("count()")
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{
        date: row.date,
        project_id: row.project_id,
        vcpus: row.vcpus,
        memory_gb: div(row.memory_mb, 1024),
        duration_ms: to_integer(row.duration_ms),
        actions: to_integer(row.actions)
      }
    end)
  end

  # The billed share is the difference of two whole-cent runner charges,
  # while the value is rounded to the nearest cent, so the two can disagree
  # by a cent. Billing more than the usage is worth would read as an error.
  defp at_most(billed, gross), do: if(Money.compare(billed, gross) == 1, do: gross, else: billed)

  # Resolved to the nearest cent once, from the unrounded amount: shape
  # multipliers are whole basis points (2 vCPU / 4 GB is 8,333), so flooring
  # would put every round number a cent short of the quoted rate.
  defp cost(compute_unit_ms), do: Money.new(round(Prepaid.on_demand_dollars(:linux, compute_unit_ms) * 100), :USD)

  defp row_units(row), do: compute_unit_ms(row.duration_ms, row.vcpus, row.memory_gb)

  # Milliseconds on the Linux baseline machine the runner Price is quoted for.
  defp compute_unit_ms(ms, vcpus, memory_gb),
    do: div(ms * Catalog.billing_multiplier(:linux, vcpus, memory_gb), Catalog.compute_unit_basis_points())

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
