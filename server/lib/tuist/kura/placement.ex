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

  Relocation reads a fortnight. What it has to be sure of is that the majority
  genuinely moved, which is a question about rate and spread rather than about
  elapsed time: 140 runs at a 60% majority spread over five separate days
  demands the same daily rate a month-long window did, and a slightly wider
  share of the window's days, so shortening the span tightens the evidence
  rather than weakening it. The month was also longer than the origin history
  it reads, which meant every account whose placement predated origin
  attribution had to wait out a window it could not yet fill before anything
  could move it — the accounts most likely to be in the wrong region were the
  ones the rung reached last.

  Where an account's served hits are read, they decide about the regions it
  already holds. Runs count where builds report from, and on a large part of
  the fleet that is not where cache traffic lands: a run weighs the same
  whether it made eight requests or thousands, and machines that report a
  build are not always the machines pulling from the cache. So the primary
  follows the hits to a region the account holds, and a secondary retires once
  what it served stops paying for the claim it reserves.

  A region the account does not hold has served it nothing to read, so it is
  read from where the account's hits come from: the signed origin each request
  carries, mapped through `OriginMap` like a run's. Where at least half the
  account's hits carry one, origins open regions and move the primary to one it
  does not hold, against floors well above the retirement ones. Elsewhere runs
  still do, as a trial the retirement rung judges on what the region then
  serves. Neither reopens a region the hits closed recently.
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
        window_days: 14,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 5
      },
      expand: %{window_days: 14, min_runs_per_day: 100, min_active_days: 7},
      retire: %{window_days: 90, max_runs_per_day: 20},
      relocation_window_days: 90,
      max_relocations_per_window: 1
    },
    pro: %{
      max_instances: 5,
      correct_initial: %{
        window_days: 7,
        majority_share: 0.8,
        min_runs_per_day: 5,
        min_active_days: 1,
        within_days: 14
      },
      relocate: %{
        window_days: 14,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 5
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
        window_days: 14,
        majority_share: 0.6,
        min_runs_per_day: 10,
        min_active_days: 5
      },
      # Pro's floor, not a higher one: the paid plans fund the same five
      # instances, so neither demands more traffic to open one. What the floor
      # has to be is an absolute rate a real second site clears and a handful of
      # stragglers does not, and 25 a day is that rate whatever the plan.
      # Measured against the fleet on 2026-09-07: it opens a region for the
      # accounts whose second site runs 30-40 builds a day, and still refuses
      # the 5-runs-a-day tails.
      expand: %{window_days: 14, min_runs_per_day: 25, min_active_days: 7},
      retire: %{window_days: 90, max_runs_per_day: 10},
      relocation_window_days: 90,
      max_relocations_per_window: 1
    }
  }

  # What the served-hits rungs read, the same for every plan. A secondary costs
  # the account's whole claim in its region and refuses claim growth
  # everywhere when that region is full, so what it has to earn is measured
  # against what it reserves.
  @served_policy %{
    relocate: %{window_days: 14, majority_share: 0.6, min_active_days: 5, min_hits_per_day: 1_000},
    retire: %{window_days: 28, max_share: 0.03, max_hits_per_gib_day: 25, min_reported_days: 21},
    expand: %{
      window_days: 14,
      min_active_days: 7,
      min_share: 0.1,
      min_hits_per_gib_day: 100,
      reopen_after_days: 90
    },
    origin: %{min_coverage: 0.5}
  }

  def default_policy, do: @default_policy

  def served_policy, do: @served_policy

  @doc """
  The longest span a served-hits rung reads, so a caller loads exactly the
  rollups it can use.
  """
  def served_window_days(served_policy \\ @served_policy) do
    max(served_policy.relocate.window_days, served_policy.retire.window_days)
  end

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
      availability, any per-plan budget and room have had their say; a region
      with no room for its instance is left out unless the account already
      holds it
    * `:primary` - the region serving the account today, or `nil`
    * `:serving` - every region it holds, primary and retiring ones included
    * `:retiring` - the ones already on their way out, which no transition
      proposes anything further about until they are gone
    * `:held_since` - when the account started holding each region, so a region
      younger than the retirement window is not given up before it has had the
      window to prove itself
    * `:relocations_in_window` - applied relocations inside the cap's window
    * `:today` - the evaluation date

  And, when the account reads served hits, all five of:

    * `:served` - the hits each public region it holds served, per day
    * `:reported` - the days each of those regions delivered a usage report,
      which is what tells a day with no hits from a day nobody heard from
    * `:reserved_gib` - what each region it holds reserves
    * `:projected_gib` - what each public region would reserve if it held it
    * `:given_up` - the regions it left within the reopening window, with the
      date it left them

  Returns `{:relocate, from, to, evidence}`, `{:expand, to, evidence}`,
  `{:retire, from, evidence}`, or `:none`.
  """
  def evaluate(context, policy \\ @default_policy, served_policy \\ @served_policy) do
    plan_policy = Map.get(policy, context.plan, policy.air)
    runs = by_region_and_date(context, :run_count)
    served = served(context)

    correct_initial(context, plan_policy, runs) ||
      relocate_to_hits(context, plan_policy, served, served_policy) ||
      relocate_to_origin_hits(context, plan_policy, served, served_policy) ||
      relocate(context, plan_policy, runs, served, served_policy) ||
      expand(context, plan_policy, runs, served, served_policy) ||
      retire_idle(context, served, served_policy) ||
      retire(context, plan_policy, runs, served, served_policy) ||
      :none
  end

  defp served(%{served: served} = context) do
    %{
      hits: served,
      origin_hits: by_region_and_date(context, :hit_count),
      reported: Map.get(context, :reported, %{}),
      reserved_gib: Map.get(context, :reserved_gib, %{}),
      projected_gib: Map.get(context, :projected_gib, %{}),
      given_up: Map.get(context, :given_up, %{})
    }
  end

  defp served(_context), do: nil

  # Origins are mapped here rather than at write time, so a corrected mapping
  # table re-reads the history it was wrong about.
  defp by_region_and_date(context, count) do
    permitted = context.permitted

    context.rollups
    |> Enum.flat_map(fn rollup ->
      case OriginMap.preferred(rollup.origin, permitted) do
        nil -> []
        region -> [{region, rollup.date, Map.get(rollup, count, 0)}]
      end
    end)
    |> Enum.group_by(fn {region, _date, _count} -> region end, fn {_region, date, count} -> {date, count} end)
  end

  # Corrects a first placement, which is a guess rather than a decision.
  #
  # An account's first region is chosen the moment a build first asks where to
  # send cache traffic, from whatever origin history exists then — for a new
  # account, often a single day of it. `relocate` needs 140 runs over a
  # fortnight at a 60% majority and fires once a quarter, so a guess made on a
  # day of evidence would otherwise stand for weeks. What justifies that
  # slowness is the cost of being wrong, and that cost is not constant: moving
  # an account whose cache is days old and nearly cold is cheap, moving one
  # with a warm working set is not.
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

  # The primary follows the hits to a region the account already holds.
  #
  # The destination is warm, so the move costs no refill. A region the account
  # does not hold has served nothing to read, so a move there is read from the
  # origins of the hits, or from runs where too few of them carry one.
  #
  # It spends the same quarterly relocation as the other relocation rungs, so
  # they cannot take turns moving an account back and forth.
  defp relocate_to_hits(_context, _plan_policy, nil, _served_policy), do: nil
  defp relocate_to_hits(%{primary: nil}, _plan_policy, _served, _served_policy), do: nil

  defp relocate_to_hits(context, plan_policy, served, served_policy) do
    rung = served_policy.relocate

    if context.relocations_in_window >= plan_policy.max_relocations_per_window do
      nil
    else
      window = window_range(context.today, rung.window_days)
      totals = totals_in(served.hits, window)
      total = totals |> Map.values() |> Enum.sum()

      candidate =
        totals
        |> Enum.filter(fn {region, _hits} -> region in context.serving end)
        |> Enum.reject(fn {region, _hits} -> region == context.primary or region in context.retiring end)
        |> Enum.max_by(fn {_region, hits} -> hits end, fn -> nil end)

      with {region, region_hits} <- candidate,
           true <- total >= rung.min_hits_per_day * rung.window_days,
           true <- region_hits / total >= rung.majority_share,
           active = active_days(served.hits, region, window),
           true <- active >= rung.min_active_days do
        evidence =
          "majority_of_hits_moved"
          |> served_evidence(rung.window_days, region_hits, total, active)
          |> Map.put("retire_source", idle?(context, served, served_policy.retire, context.primary))

        {:relocate, context.primary, region, evidence}
      else
        _ -> nil
      end
    end
  end

  # The primary moves to a region the account does not hold once the majority
  # of its hits come from origins nearer that region. The same rung as the runs
  # one, read in hits: a build that made forty thousand requests weighs forty
  # thousand, not one.
  defp relocate_to_origin_hits(_context, _plan_policy, nil, _served_policy), do: nil
  defp relocate_to_origin_hits(%{primary: nil}, _plan_policy, _served, _served_policy), do: nil

  defp relocate_to_origin_hits(context, plan_policy, served, served_policy) do
    rung = served_policy.relocate

    if context.relocations_in_window >= plan_policy.max_relocations_per_window or
         not attributed?(context, served, served_policy) do
      nil
    else
      window = window_range(context.today, rung.window_days)
      totals = totals_in(served.origin_hits, window)
      total = totals |> Map.values() |> Enum.sum()

      candidate =
        totals
        |> Enum.reject(fn {region, _hits} ->
          region in context.serving or recently_given_up?(context, served, served_policy.expand, region)
        end)
        |> Enum.max_by(fn {_region, hits} -> hits end, fn -> nil end)

      with {region, region_hits} <- candidate,
           true <- total >= rung.min_hits_per_day * rung.window_days,
           true <- region_hits / total >= rung.majority_share,
           active = active_days(served.origin_hits, region, window),
           true <- active >= rung.min_active_days do
        evidence =
          "majority_of_origin_hits_moved"
          |> served_evidence(rung.window_days, region_hits, total, active)
          |> Map.put("retire_source", idle?(context, served, served_policy.retire, context.primary))
          |> Map.put("origin_map_version", OriginMap.version())

        {:relocate, context.primary, region, evidence}
      else
        _ -> nil
      end
    end
  end

  # Whether enough of the account's hits carry the origin they came from for
  # origins to stand for the account: placement reads them in place of runs
  # only then. Requests from clients that predate signed origins carry none, and
  # an account mostly made of those is read from its runs as before.
  defp attributed?(context, served, served_policy) do
    window = window_range(context.today, served_policy.expand.window_days)
    served_total = served.hits |> totals_in(window) |> Map.values() |> Enum.sum()
    attributed_total = served.origin_hits |> totals_in(window) |> Map.values() |> Enum.sum()

    served_total > 0 and attributed_total / served_total >= served_policy.origin.min_coverage
  end

  defp relocate(_context, %{relocate: nil}, _runs, _served, _served_policy), do: nil

  # Nothing to relocate from. Reachable only for an account whose every
  # instance is a warm handoff's transient row, which is not a placement to
  # move.
  defp relocate(%{primary: nil}, _plan_policy, _runs, _served, _served_policy), do: nil

  defp relocate(context, plan_policy, runs, served, served_policy) do
    if context.relocations_in_window >= plan_policy.max_relocations_per_window or
         (served != nil and attributed?(context, served, served_policy)) do
      nil
    else
      rung = plan_policy.relocate
      window = window_range(context.today, rung.window_days)
      totals = totals_in(runs, window)
      total = totals |> Map.values() |> Enum.sum()

      candidate =
        totals
        |> Enum.reject(fn {region, _runs} ->
          region == context.primary or region in context.retiring or
            decided_by_hits?(context, served, served_policy, region) or
            recently_given_up?(context, served, served_policy.expand, region)
        end)
        |> Enum.max_by(fn {_region, region_runs} -> region_runs end, fn -> nil end)

      with {region, region_runs} <- candidate,
           true <- total >= rung.min_runs_per_day * rung.window_days,
           true <- region_runs / total >= rung.majority_share,
           active = active_days(runs, region, window),
           true <- active >= rung.min_active_days do
        evidence =
          "majority_of_runs_moved"
          |> evidence(rung, region_runs, total, active)
          |> Map.put("retire_source", retire_source?(context, plan_policy, runs, served, served_policy))

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
  #
  # Where the region's own hits have been heard, they answer instead of its
  # runs, for the same reason the retirement rung reads them.
  defp retire_source?(context, plan_policy, runs, served, served_policy) do
    cond do
      length(context.serving) >= plan_policy.max_instances ->
        true

      reported?(context, served, served_policy.retire, context.primary) ->
        idle?(context, served, served_policy.retire, context.primary)

      is_nil(plan_policy.retire) ->
        true

      true ->
        not earns_its_place?(context, plan_policy, runs, context.primary)
    end
  end

  # A region the account holds and whose hits placement reads. The hits rungs
  # decide about those, so the runs rungs neither move the primary onto one nor
  # retire one.
  defp decided_by_hits?(_context, nil, _served_policy, _region), do: false

  defp decided_by_hits?(context, served, served_policy, region) do
    region in context.serving and reported?(context, served, served_policy.retire, region)
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

  defp expand(_context, %{expand: nil}, _runs, _served, _served_policy), do: nil

  defp expand(context, plan_policy, runs, served, served_policy) do
    cond do
      length(context.serving) >= plan_policy.max_instances ->
        nil

      served != nil and attributed?(context, served, served_policy) ->
        expand_on_origin_hits(context, served, served_policy)

      true ->
        expand_on_runs(context, plan_policy, runs, served, served_policy)
    end
  end

  defp expand_on_runs(context, plan_policy, runs, served, served_policy) do
    rung = plan_policy.expand
    window = window_range(context.today, rung.window_days)
    totals = totals_in(runs, window)
    total = totals |> Map.values() |> Enum.sum()

    candidate =
      totals
      |> Enum.reject(fn {region, _runs} -> region in context.serving end)
      |> Enum.filter(fn {region, region_runs} ->
        region_runs >= rung.min_runs_per_day * rung.window_days and
          active_days(runs, region, window) >= rung.min_active_days and
          not recently_given_up?(context, served, served_policy.expand, region)
      end)
      |> Enum.max_by(fn {_region, region_runs} -> region_runs end, fn -> nil end)

    case candidate do
      nil ->
        nil

      {region, region_runs} ->
        {:expand, region, evidence("sustained_local_demand", rung, region_runs, total, active_days(runs, region, window))}
    end
  end

  # Opens a region once the hits from origins nearer it would keep it well clear
  # of retirement: a tenth of the account's attributed hits, or four times the
  # hits per reserved GiB a secondary retires under, against what the region
  # would reserve. The gap to the retirement floors is what stops a region
  # opened on this evidence being retired by the rung that judges it next.
  defp expand_on_origin_hits(context, served, served_policy) do
    rung = served_policy.expand
    window = window_range(context.today, rung.window_days)
    totals = totals_in(served.origin_hits, window)
    total = totals |> Map.values() |> Enum.sum()

    totals
    |> Enum.reject(fn {region, _hits} -> region in context.serving end)
    |> Enum.filter(fn {region, region_hits} ->
      active_days(served.origin_hits, region, window) >= rung.min_active_days and
        not recently_given_up?(context, served, rung, region) and
        earns_a_claim?(served, rung, region, region_hits, total, window)
    end)
    |> Enum.max_by(fn {_region, region_hits} -> region_hits end, fn -> nil end)
    |> case do
      nil ->
        nil

      {region, region_hits} ->
        evidence =
          "projected_hits"
          |> served_evidence(rung.window_days, region_hits, total, active_days(served.origin_hits, region, window))
          |> Map.merge(%{
            "projected_gib" => Map.get(served.projected_gib, region),
            "hits_per_active_day" => hits_per_active_day(served, region_hits, window),
            "origin_map_version" => OriginMap.version()
          })

        {:expand, region, evidence}
    end
  end

  defp earns_a_claim?(served, rung, region, region_hits, total, window) do
    region_hits / total >= rung.min_share or
      case Map.get(served.projected_gib, region) do
        nil -> false
        gib -> hits_per_active_day(served, region_hits, window) >= rung.min_hits_per_gib_day * gib
      end
  end

  # A region the hits closed stays shut for the reopening window, to an
  # expansion and to the primary alike, whichever evidence would reopen it. Leaving it was decided on what it served, which
  # outranks a projection from runs or from origins: both read the region
  # through `OriginMap`, and a client the map places near a region is not always
  # one DNS routes to it. Without this the rungs undo each other a month apart.
  #
  # Where runs are what opens a region, the opening is a trial the retirement
  # rung judges on what the region then serves. Run share forecasts that poorly
  # in both directions, so it does not gate the opening.
  defp recently_given_up?(_context, nil, _rung, _region), do: false

  defp recently_given_up?(context, served, rung, region) do
    case Map.get(served.given_up, region) do
      nil -> false
      given_up_on -> Date.diff(context.today, given_up_on) < rung.reopen_after_days
    end
  end

  # A secondary retires once what it served stops paying for what it reserves.
  #
  # Both have to hold: a small share of the account's hits, and few hits for
  # the claim it holds. A share alone would let a busy primary veto every other
  # region, since a second site serving thousands of hits a day is a small share
  # of an account serving millions, and a rate alone would keep a region for an
  # account so busy that a rounding error of it clears any floor.
  #
  # Four weeks rather than the quarter the runs rung waits. That one reads an
  # absence through a proxy and has to be sure; this one reads the absence
  # itself, on days the region is known to have reported, and every week it
  # waits is a week the whole claim stays reserved for nothing.
  defp retire_idle(_context, nil, _served_policy), do: nil

  defp retire_idle(context, served, served_policy) do
    rung = served_policy.retire
    window = window_range(context.today, rung.window_days)
    totals = totals_in(served.hits, window)

    context.serving
    |> Enum.reject(&(&1 == context.primary or &1 in context.retiring))
    |> Enum.filter(&(held_long_enough?(context, &1, rung.window_days) and idle?(context, served, rung, &1)))
    |> Enum.min_by(&Map.get(totals, &1, 0), fn -> nil end)
    |> case do
      nil ->
        nil

      region ->
        total = totals |> Map.values() |> Enum.sum()
        region_hits = Map.get(totals, region, 0)

        evidence =
          "hits_below_floor"
          |> served_evidence(rung.window_days, region_hits, total, active_days(served.hits, region, window))
          |> Map.merge(%{
            "reserved_gib" => Map.get(served.reserved_gib, region, 0),
            "reported_days" => reported_days(served, region, window),
            "hits_per_active_day" => hits_per_active_day(served, region_hits, window)
          })

        {:retire, region, evidence}
    end
  end

  # Whether `region` served too little for what it reserves, over a window it
  # reported through. A region that went unheard for part of the window is not
  # judged on it: that is the one case where no hits is not evidence of none.
  defp idle?(context, served, rung, region) do
    window = window_range(context.today, rung.window_days)
    totals = totals_in(served.hits, window)
    total = totals |> Map.values() |> Enum.sum()
    region_hits = Map.get(totals, region, 0)
    share = if total > 0, do: region_hits / total, else: 0.0
    floor = rung.max_hits_per_gib_day * Map.get(served.reserved_gib, region, 0)

    reported?(context, served, rung, region) and share <= rung.max_share and
      hits_per_active_day(served, region_hits, window) <= floor
  end

  defp reported?(_context, nil, _rung, _region), do: false

  defp reported?(context, served, rung, region) do
    reported_days(served, region, window_range(context.today, rung.window_days)) >= rung.min_reported_days
  end

  defp reported_days(served, region, window) do
    served.reported
    |> Map.get(region, [])
    |> Enum.count(&(&1 in window))
  end

  # Per day the account used the cache at all, rather than per calendar day: a
  # team that builds five days a week is not a fifth quieter for it, and an
  # account that started using the cache halfway through the window is judged
  # on the half it was there for.
  defp hits_per_active_day(served, region_hits, window) do
    account_days =
      served.hits
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(fn {date, hits} -> date in window and hits > 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> length()

    if account_days > 0, do: region_hits / account_days, else: 0.0
  end

  defp retire(_context, %{retire: nil}, _runs, _served, _served_policy), do: nil

  defp retire(context, plan_policy, runs, served, served_policy) do
    rung = plan_policy.retire
    window = window_range(context.today, rung.window_days)
    totals = totals_in(runs, window)
    total = totals |> Map.values() |> Enum.sum()

    cond do
      # An account with nothing attributed anywhere is not an account whose
      # regions are misplaced; it is one nobody could locate, or one that has
      # gone quiet everywhere. Reading that as "this region is unused" would
      # retire every secondary in the fleet on the strength of no evidence at
      # all, which is exactly what the rollout looks like before origins are
      # being attributed.
      total == 0 ->
        nil

      not history_covers_window?(context, rung.window_days) ->
        nil

      true ->
        retire_candidate(
          context,
          plan_policy,
          rung,
          totals,
          total,
          runs,
          window,
          &decided_by_hits?(context, served, served_policy, &1)
        )
    end
  end

  # Retirement is the only rung that reads an absence, so it is the only one
  # partial history makes *more* likely to fire. The others need runs to clear
  # a floor and a short history simply withholds them; this one needs runs to
  # be missing, and a window nobody was watching supplies that for every region
  # at once. A floor of a whole window's runs measured against a tenth of a
  # window is a floor ten times too generous, which turns a real second office
  # into one that looks abandoned.
  #
  # `held_long_enough?` does not cover this. It asks how long the account has
  # held the region, not how much of that time anyone was recording where its
  # traffic came from, and attribution that starts after the region did
  # satisfies the first while failing the second.
  #
  # Permanent rather than a rollout guard: an account onboarded last week has a
  # week of history whatever the fleet's attribution has been doing for months,
  # and its regions must not be judged on a quarter it was not present for.
  defp history_covers_window?(%{rollups: []}, _window_days), do: false

  defp history_covers_window?(context, window_days) do
    earliest = context.rollups |> Enum.map(& &1.date) |> Enum.min(Date)

    Date.diff(context.today, earliest) >= window_days - 1
  end

  defp retire_candidate(context, plan_policy, rung, totals, total, runs, window, decided_by_hits?) do
    # Never the primary, and never the last one serving: retirement reclaims a
    # spare region, it does not take an account's cache away. Nor one whose hits
    # are read: `retire_idle` has already decided about those from what they
    # served, and runs saying otherwise is the disagreement hits settle.
    context.serving
    |> Enum.reject(&(&1 == context.primary or &1 in context.retiring or decided_by_hits?.(&1)))
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

  defp served_evidence(signal, window_days, region_hits, total, active) do
    %{
      "signal" => signal,
      "window_days" => window_days,
      "region_hits" => region_hits,
      "total_hits" => total,
      "share" => if(total > 0, do: Float.round(region_hits / total, 3), else: 0.0),
      "hits_per_day" => Float.round(region_hits / window_days, 2),
      "active_days" => active
    }
  end
end
