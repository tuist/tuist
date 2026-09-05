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
      # Two, so an account whose work is genuinely split is not forced to serve
      # half of it from the wrong side of an ocean. The floors are higher than
      # Pro's rather than lower: a second instance is the expensive thing, so a
      # plan that funds fewer of them should take more traffic to open one, not
      # less. Without a second slot every Air relocation also tore the source
      # down unconditionally (`retire_source?` has no other answer at
      # `max_instances: 1`), which is the destroy-and-cold-refill that rung
      # exists to avoid.
      max_instances: 2,
      correct_initial: %{
        window_days: 7,
        majority_share: 0.8,
        min_runs_per_day: 5,
        min_active_days: 1,
        within_days: 14
      },
      relocate: %{
        window_days: 30,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 10
      },
      expand: %{window_days: 14, min_runs_per_day: 100, min_active_days: 7},
      retire: %{window_days: 90, max_runs_per_day: 20},
      relocation_window_days: 90,
      max_relocations_per_window: 1
    },
    pro: %{
      max_instances: 3,
      correct_initial: %{
        window_days: 7,
        majority_share: 0.8,
        min_runs_per_day: 5,
        min_active_days: 1,
        within_days: 14
      },
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
      correct_initial: %{
        window_days: 7,
        majority_share: 0.8,
        min_runs_per_day: 5,
        min_active_days: 1,
        within_days: 14
      },
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
      [plan.correct_initial, plan.relocate, plan.expand, plan.retire]
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

    correct_initial(context, plan_policy, runs) ||
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

  # Corrects a first placement, which is a guess rather than a decision.
  #
  # An account's first region is chosen the moment a build first asks where to
  # send cache traffic, from whatever origin history exists then — for a new
  # account, often a single day of it. `relocate` needs 300 runs over 30 days
  # at a 60% majority and fires once a quarter, so a guess made on a week of
  # evidence would otherwise stand for months. What justifies that slowness is
  # the cost of being wrong, and that cost is not constant: moving an account
  # whose cache is days old and nearly cold is cheap, moving one with a warm
  # working set is not.
  #
  # So this is narrow rather than slow. It reads the same short window the guess
  # itself read, and it only ever runs while the primary is young AND was never
  # decided. Applying it records a placement row, which makes the primary
  # decided and disqualifies this rung for good — the once-only guarantee needs
  # no counter of its own, and correcting a guess does not spend the quarterly
  # relocation budget, because converging on the right answer for the first
  # time is not churn.
  #
  # What holds it back is the majority, not the calendar. The reason other
  # rungs wait for days to accumulate is flapping, and this one cannot flap:
  # it fires at most once per account, ever. So a day count would buy no
  # safety, and it costs the account a wrongly placed cache on every build
  # until it elapses. Worse, `within_days` expires the rung entirely, so an
  # account building a few days a week could fail to accumulate the days
  # before the window closed and fall through to a rung measured in months —
  # the outcome this exists to prevent.
  #
  # A single active day is therefore enough, and the floors that remain are
  # the ones that mean something: a clear majority, so one developer on a
  # VPN moves nothing unless they genuinely are the account's traffic, and a
  # volume floor that a real working day clears and an evaluation from a
  # conference does not.
  defp correct_initial(_context, %{correct_initial: nil}, _runs), do: nil
  defp correct_initial(%{primary: nil}, _plan_policy, _runs), do: nil
  defp correct_initial(%{primary_decided?: true}, _plan_policy, _runs), do: nil

  defp correct_initial(context, plan_policy, runs) do
    rung = plan_policy.correct_initial

    if guessed_recently?(context, rung) do
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
        {:correct, context.primary, region, evidence("initial_placement_missed", rung, region_runs, total, active)}
      else
        _ -> nil
      end
    end
  end

  # Only while the region has been held for less than the rung's reach. An
  # account past it has a cache worth keeping, and the slower rung is the one
  # that should decide.
  defp guessed_recently?(context, rung) do
    case Map.get(context.held_since, context.primary) do
      nil -> false
      held_since -> Date.diff(context.today, held_since) <= rung.within_days
    end
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
        evidence =
          "majority_of_runs_moved"
          |> evidence(rung, region_runs, total, active)
          |> Map.put("retire_source", retire_source?(context, plan_policy, runs))

        {:relocate, context.primary, region, evidence}
      else
        _ -> nil
      end
    end
  end

  # Whether the region the primary is leaving should be given up with it.
  #
  # Only when the account cannot hold it, or its own traffic does not earn it.
  # A majority moving is a statement about which region should be *primary*,
  # not about whether the other one is still worth serving: a 65/35 split
  # moves the primary, and retiring the 35 would drain a region that clears
  # the expansion floor on its own — which the very next sweep would then
  # propose expanding back into, having destroyed and cold-refilled a cache to
  # arrive exactly where it started.
  defp retire_source?(context, plan_policy, runs) do
    cond do
      length(context.serving) >= plan_policy.max_instances -> true
      is_nil(plan_policy.retire) -> true
      true -> not earns_its_place?(context, plan_policy, runs, context.primary)
    end
  end

  # A region carrying enough of its own traffic that expansion would open it
  # if the account did not already hold it.
  defp earns_its_place?(context, plan_policy, runs, region) do
    case plan_policy.expand do
      nil ->
        false

      rung ->
        window = window_range(context.today, rung.window_days)

        Map.get(totals_in(runs, window), region, 0) >= rung.min_runs_per_day * rung.window_days and
          active_days(runs, region, window) >= rung.min_active_days
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
    total = totals |> Map.values() |> Enum.sum()

    # An account with nothing attributed anywhere is not an account whose
    # regions are misplaced; it is one nobody could locate, or one that has
    # gone quiet everywhere. Reading that as "this region is unused" would
    # retire every secondary in the fleet on the strength of no evidence at
    # all, which is exactly what the rollout looks like before origins are
    # being attributed.
    if total == 0 do
      nil
    else
      retire_candidate(context, plan_policy, rung, totals, total, runs, window)
    end
  end

  defp retire_candidate(context, plan_policy, rung, totals, total, runs, window) do
    # Never the primary, and never the last one serving: retirement reclaims a
    # spare region, it does not take an account's cache away.
    context.serving
    |> Enum.reject(&(&1 == context.primary or &1 in context.retiring))
    |> Enum.filter(fn region ->
      # The two floors span different windows, so a region quiet for months
      # and busy for the last fortnight can sit under the retirement total
      # while being actively used. Giving it up would drain a cache that
      # expansion reopens on the next sweep, so the last word goes to the
      # rung that would reopen it.
      held_long_enough?(context, region, rung.window_days) and
        Map.get(totals, region, 0) <= rung.max_runs_per_day * rung.window_days and
        not earns_its_place?(context, plan_policy, runs, region)
    end)
    |> Enum.min_by(&Map.get(totals, &1, 0), fn -> nil end)
    |> case do
      nil ->
        nil

      region ->
        region_runs = Map.get(totals, region, 0)

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
