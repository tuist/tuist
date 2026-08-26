defmodule Tuist.Kura.Placement do
  @moduledoc """
  Decides where one account's cache instances belong from where its traffic
  comes from. Pure: origin rollups in, at most one proposed transition out.

  Three transitions, one mechanism. The primary **relocates** when another
  region has durably carried the majority of the account's runs. A paid
  account **expands** into a region whose own traffic clears an absolute
  floor, share-blind on purpose: a heavy second site deserves a local instance
  even while the first site dominates the mix, and a share test would let a
  large primary veto every other region forever. A secondary **retires** when
  its region's traffic falls under a much lower floor, the gap between the two
  being what stops it flapping.

  Windows are calendar spans rather than runs of qualifying days: nobody
  builds seven days a week, and a policy that broke its streak on a quiet
  weekend would never fire for a normal team. Volume is therefore read as a
  total across the span, with a separate count of the days that saw traffic
  so a single burst cannot pass for a durable move.
  """

  alias Tuist.Kura.OriginMap

  @default_policy %{
    air: %{
      # One instance, so nothing to expand into or retire.
      max_instances: 1,
      relocate: %{
        window_days: 30,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 10
      },
      expand: nil,
      retire: nil,
      relocation_window_days: 90,
      max_relocations_per_window: 1
    },
    pro: %{
      max_instances: 3,
      relocate: %{
        window_days: 30,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 10
      },
      expand: %{window_days: 14, min_runs_per_day: 25, min_active_days: 7},
      retire: %{window_days: 90, max_runs_per_day: 5},
      relocation_window_days: 90,
      max_relocations_per_window: 1
    },
    enterprise: %{
      max_instances: 5,
      relocate: %{
        window_days: 30,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 10
      },
      expand: %{window_days: 14, min_runs_per_day: 50, min_active_days: 7},
      retire: %{window_days: 90, max_runs_per_day: 10},
      relocation_window_days: 90,
      max_relocations_per_window: 1
    }
  }

  def default_policy, do: @default_policy

  @doc """
  The longest span any rung reads, so a caller loads exactly the rollups the
  policy can use.
  """
  def window_days(policy \\ @default_policy) do
    policy
    |> Map.values()
    |> Enum.flat_map(fn plan ->
      [plan.relocate, plan.expand, plan.retire]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.window_days)
    end)
    |> Enum.max()
  end

  @doc """
  Evaluates one account's origin rollups against the policy.

  Takes a context map with:

    * `:plan` - the account's plan (`:air`, `:pro`, or `:enterprise`)
    * `:rollups` - `Tuist.Kura.OriginRollup` rows (or maps with the same keys)
      covering the policy windows
    * `:permitted` - the regions the account may be placed in, after residency,
      availability and any per-plan budget have had their say
    * `:primary` - the region serving the account today, or `nil`
    * `:serving` - every region it holds, primary and retiring ones included
    * `:retiring` - the ones already on their way out, which no transition
      proposes anything further about until they are gone
    * `:held_since` - when the account started holding each region, so a region
      younger than the retirement window is not given up before it has had the
      window to prove itself
    * `:relocations_in_window` - applied relocations inside the cap's window
    * `:today` - the evaluation date

  Returns `{:relocate, from, to, evidence}`, `{:expand, to, evidence}`,
  `{:retire, from, evidence}`, or `:none`.
  """
  def evaluate(context, policy \\ @default_policy) do
    plan_policy = Map.get(policy, context.plan, policy.air)
    runs = runs_by_region_and_date(context)

    relocate(context, plan_policy, runs) ||
      expand(context, plan_policy, runs) ||
      retire(context, plan_policy, runs) ||
      :none
  end

  # Origins are mapped here rather than at write time, so a corrected mapping
  # table re-reads the history it was wrong about.
  defp runs_by_region_and_date(context) do
    permitted = context.permitted

    context.rollups
    |> Enum.flat_map(fn rollup ->
      case OriginMap.preferred(rollup.origin, permitted) do
        nil -> []
        region -> [{region, rollup.date, rollup.run_count}]
      end
    end)
    |> Enum.group_by(fn {region, _date, _runs} -> region end, fn {_region, date, runs} -> {date, runs} end)
  end

  defp relocate(_context, %{relocate: nil}, _runs), do: nil

  # Nothing to relocate from. Reachable only for an account whose every
  # instance is a warm handoff's transient row, which is not a placement to
  # move.
  defp relocate(%{primary: nil}, _plan_policy, _runs), do: nil

  defp relocate(context, plan_policy, runs) do
    if context.relocations_in_window >= plan_policy.max_relocations_per_window do
      nil
    else
      rung = plan_policy.relocate
      window = window_range(context.today, rung.window_days)
      totals = totals_in(runs, window)
      total = totals |> Map.values() |> Enum.sum()

      candidate =
        totals
        |> Enum.reject(fn {region, _runs} -> region == context.primary or region in context.retiring end)
        |> Enum.max_by(fn {_region, region_runs} -> region_runs end, fn -> nil end)

      with {region, region_runs} <- candidate,
           true <- total >= rung.min_runs_per_day * rung.window_days,
           true <- region_runs / total >= rung.majority_share,
           active = active_days(runs, region, window),
           true <- active >= rung.min_active_days do
        {:relocate, context.primary, region, evidence("majority_of_runs_moved", rung, region_runs, total, active)}
      else
        _ -> nil
      end
    end
  end

  defp expand(_context, %{expand: nil}, _runs), do: nil

  defp expand(context, plan_policy, runs) do
    if length(context.serving) >= plan_policy.max_instances do
      nil
    else
      rung = plan_policy.expand
      window = window_range(context.today, rung.window_days)
      totals = totals_in(runs, window)

      candidate =
        totals
        |> Enum.reject(fn {region, _runs} -> region in context.serving end)
        |> Enum.filter(fn {region, region_runs} ->
          region_runs >= rung.min_runs_per_day * rung.window_days and
            active_days(runs, region, window) >= rung.min_active_days
        end)
        |> Enum.max_by(fn {_region, region_runs} -> region_runs end, fn -> nil end)

      case candidate do
        nil ->
          nil

        {region, region_runs} ->
          total = totals |> Map.values() |> Enum.sum()

          {:expand, region,
           evidence("sustained_local_demand", rung, region_runs, total, active_days(runs, region, window))}
      end
    end
  end

  defp retire(_context, %{retire: nil}, _runs), do: nil

  defp retire(context, plan_policy, runs) do
    rung = plan_policy.retire
    window = window_range(context.today, rung.window_days)
    totals = totals_in(runs, window)

    # Never the primary, and never the last one serving: retirement reclaims a
    # spare region, it does not take an account's cache away.
    context.serving
    |> Enum.reject(&(&1 == context.primary or &1 in context.retiring))
    |> Enum.filter(fn region ->
      held_long_enough?(context, region, rung.window_days) and
        Map.get(totals, region, 0) <= rung.max_runs_per_day * rung.window_days
    end)
    |> Enum.min_by(&Map.get(totals, &1, 0), fn -> nil end)
    |> case do
      nil ->
        nil

      region ->
        region_runs = Map.get(totals, region, 0)
        total = totals |> Map.values() |> Enum.sum()

        {:retire, region, evidence("demand_below_floor", rung, region_runs, total, active_days(runs, region, window))}
    end
  end

  # A region cannot have spent the retirement window below the floor if the
  # account has not held it that long. Without this the two floors do not
  # actually straddle anything: a region opened on a fortnight's traffic
  # carries less than the retirement window's worth of runs on the very day it
  # opens, so it would be given up again immediately and reopened by the same
  # evidence the next fortnight.
  defp held_long_enough?(context, region, window_days) do
    case Map.get(context.held_since, region) do
      nil -> true
      held_since -> Date.diff(context.today, held_since) >= window_days
    end
  end

  defp window_range(today, window_days) do
    Date.range(Date.add(today, -(window_days - 1)), today)
  end

  defp totals_in(runs, window) do
    Map.new(runs, fn {region, entries} ->
      {region, entries |> Enum.filter(&in_window?(&1, window)) |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
    end)
  end

  # Days that actually saw traffic, which is what separates a durable move from
  # one afternoon's burst of the same volume.
  defp active_days(runs, region, window) do
    runs
    |> Map.get(region, [])
    |> Enum.filter(&(in_window?(&1, window) and elem(&1, 1) > 0))
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> length()
  end

  defp in_window?({date, _runs}, window), do: date in window

  defp evidence(signal, rung, region_runs, total, active) do
    %{
      "signal" => signal,
      "window_days" => rung.window_days,
      "region_runs" => region_runs,
      "total_runs" => total,
      "share" => if(total > 0, do: Float.round(region_runs / total, 3), else: 0.0),
      "runs_per_day" => Float.round(region_runs / rung.window_days, 2),
      "active_days" => active,
      "origin_map_version" => OriginMap.version()
    }
  end
end
