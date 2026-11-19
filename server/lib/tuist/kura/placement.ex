defmodule Tuist.Kura.Placement do
  @moduledoc """
  Decides where one account's cache instances belong from where its cache
  traffic comes from. Pure: rollups in, at most one proposed transition out.

  Everything is read in hits, the requests a region served, because a hit is
  what a cache instance is for. Runs count where builds report from, and on a
  large part of the fleet that is not where cache traffic lands: a run weighs
  the same whether it made eight requests or thousands, and machines that
  report a build are not always the machines pulling from the cache. Regions
  opened on runs went on to serve a percent or two of the account's traffic.

  The regions an account holds are read from what they served. The primary
  follows the hits to a held region carrying their majority, and a secondary
  retires once what it served stops paying for the claim it reserves.

  A region the account does not hold has served it nothing to read, so it is
  read from where the account's hits come from: the signed origin each request
  carries, mapped through `OriginMap`. Only where at least half the account's
  hits carry one, since a partial reading would mistake the attributed clients
  for the account; below that nothing opens a region or moves the primary to
  one it does not hold. The floors for opening sit well above the retirement
  ones, which is what stops a region flapping, and nothing reopens a region
  the hits closed recently.

  The one rung that still reads runs is the correction of a first placement,
  which is a guess made on whatever an account's first day looked like, before
  any region of it has served anything.

  Windows are calendar spans rather than runs of qualifying days: nobody
  builds seven days a week, and a policy that broke its streak on a quiet
  weekend would never fire for a normal team. Volume is therefore read as a
  total across the span, with a separate count of the days that saw traffic
  so a single burst cannot pass for a durable move.
  """

  alias Tuist.Kura.OriginMap

  @correct_initial %{
    window_days: 7,
    majority_share: 0.8,
    min_runs_per_day: 5,
    min_active_days: 1,
    within_days: 14
  }

  @default_policy %{
    air: %{
      # One. Air is free, and a second instance reserves the account's whole
      # claim in another region, so Air never expands: an account whose
      # traffic moves has its primary moved after it, and the region it leaves
      # is given up. That is a cold refill on every Air relocation, which a free
      # cache can take. An Air account still holding a second region from when
      # Air had two gives it up through `retire_over_cap`.
      max_instances: 1,
      correct_initial: @correct_initial,
      relocation_window_days: 90,
      max_relocations_per_window: 1
    },
    pro: %{
      max_instances: 5,
      correct_initial: @correct_initial,
      relocation_window_days: 90,
      max_relocations_per_window: 1
    },
    enterprise: %{
      max_instances: 5,
      correct_initial: @correct_initial,
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
    retire_zero_hits: %{window_days: 10},
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
    Enum.max([
      served_policy.relocate.window_days,
      served_policy.retire.window_days,
      served_policy.retire_zero_hits.window_days + 1
    ])
  end

  @doc """
  The longest span any rung reads origin rollups over, so a caller loads
  exactly the rollups the policy can use: the runs the first-placement
  correction reads, the origin hits expansion and relocation read, and what
  over-cap retirement ranks secondaries by when the account reads no served
  hits.
  """
  def window_days(policy \\ @default_policy, served_policy \\ @served_policy) do
    Enum.max(
      Enum.map(Map.values(policy), & &1.correct_initial.window_days) ++
        [
          served_policy.relocate.window_days,
          served_policy.expand.window_days,
          served_policy.retire.window_days
        ]
    )
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
    served = served(context)

    move_primary(context, plan_policy, served, served_policy) ||
      retire_over_cap(context, plan_policy, served, served_policy) ||
      expand(context, plan_policy, served, served_policy) ||
      retire_zero_hits(context, served, served_policy) ||
      retire_idle(context, served, served_policy) ||
      :none
  end

  defp move_primary(context, plan_policy, served, served_policy) do
    correct_initial(context, plan_policy, by_region_and_date(context, :run_count)) ||
      relocate_to_hits(context, plan_policy, served, served_policy) ||
      relocate_to_origin_hits(context, plan_policy, served, served_policy)
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
  # account, often a single day of it. The hits rungs need a fortnight of
  # served traffic and fire once a quarter, so a guess made on a day of
  # evidence would otherwise stand for weeks. What justifies that
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
  # origins of the hits.
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
          |> Map.put(
            "retire_source",
            over_cap?(context, plan_policy, 0) or idle?(context, served, served_policy.retire, context.primary)
          )

        {:relocate, context.primary, region, evidence}
      else
        _ -> nil
      end
    end
  end

  # The primary moves to a region the account does not hold once the majority
  # of its hits come from origins nearer that region. Read in hits rather than
  # runs: a build that made forty thousand requests weighs forty thousand, not
  # one.
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
          |> Map.put(
            "retire_source",
            over_cap?(context, plan_policy, 1) or idle?(context, served, served_policy.retire, context.primary)
          )
          |> Map.put("origin_map_version", OriginMap.version())

        {:relocate, context.primary, region, evidence}
      else
        _ -> nil
      end
    end
  end

  # Whether enough of the account's hits carry the origin they came from for
  # origins to stand for the account. Requests whose credential carries no
  # signed origin say nothing about where they came from, and below this an
  # account opens no region and moves its primary to none it does not hold.
  defp attributed?(context, served, served_policy) do
    window = window_range(context.today, served_policy.expand.window_days)
    served_total = served.hits |> totals_in(window) |> Map.values() |> Enum.sum()
    attributed_total = served.origin_hits |> totals_in(window) |> Map.values() |> Enum.sum()

    served_total > 0 and attributed_total / served_total >= served_policy.origin.min_coverage
  end

  # Only into a second region of an account already served somewhere, and only
  # read from origin hits: a region the account does not hold has served it
  # nothing, and where too few of its hits carry an origin there is no reading
  # of where the rest come from.
  defp expand(%{primary: nil}, _plan_policy, _served, _served_policy), do: nil
  defp expand(_context, _plan_policy, nil, _served_policy), do: nil

  defp expand(context, plan_policy, served, served_policy) do
    if length(context.serving) < plan_policy.max_instances and attributed?(context, served, served_policy) do
      expand_on_origin_hits(context, served, served_policy)
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
  # expansion and to the primary alike. Leaving it was decided on what it
  # served, which outranks a projection from origins: they read the region
  # through `OriginMap`, and a client the map places near a region is not always
  # one DNS routes to it. Without this the rungs undo each other a month apart.
  defp recently_given_up?(context, served, rung, region) do
    case Map.get(served.given_up, region) do
      nil -> false
      given_up_on -> Date.diff(context.today, given_up_on) < rung.reopen_after_days
    end
  end

  # Whether the account would hold more regions than its plan funds once it
  # opens `opening` more. Retiring regions are already on their way out.
  defp over_cap?(context, plan_policy, opening) do
    length(context.serving -- context.retiring) + opening > plan_policy.max_instances
  end

  # An account holding more regions than its plan funds gives up a secondary,
  # the one that carried the least of its traffic, without waiting for the
  # retirement floors: its plan does not fund the region however busy it is.
  # This is how Air accounts let go of the second region Air used to fund. It
  # runs after the relocation rungs, so an account whose traffic moved to its
  # secondary moves its primary there first and gives up the old one with it.
  defp retire_over_cap(context, plan_policy, served, served_policy) do
    if over_cap?(context, plan_policy, 0) do
      window_days = served_policy.retire.window_days
      window = window_range(context.today, window_days)

      # What each region served where that is read, otherwise where the
      # account's hits come from. Either only ranks which secondary goes
      # first: the plan decides that one does.
      traffic = if served == nil, do: by_region_and_date(context, :hit_count), else: served.hits
      totals = totals_in(traffic, window)

      context.serving
      |> Enum.reject(&(&1 == context.primary or &1 in context.retiring))
      |> Enum.min_by(&Map.get(totals, &1, 0), fn -> nil end)
      |> case do
        nil ->
          nil

        region ->
          {:retire, region,
           %{
             "signal" => "over_instance_cap",
             "window_days" => window_days,
             "region_traffic" => Map.get(totals, region, 0),
             "total_traffic" => totals |> Map.values() |> Enum.sum(),
             "max_instances" => plan_policy.max_instances
           }}
      end
    end
  end

  # Zero hits can retire a secondary sooner, but only after every complete
  # day reported. Today's partial row may veto retirement, never establish it.
  defp retire_zero_hits(_context, nil, _served_policy), do: nil

  defp retire_zero_hits(context, served, served_policy) do
    days = served_policy.retire_zero_hits.window_days
    window = Date.range(Date.add(context.today, -days), Date.add(context.today, -1))
    totals = totals_in(served.hits, window)
    today_hits = totals_in(served.hits, Date.range(context.today, context.today))
    serving = context.serving -- context.retiring

    Enum.find_value(serving, fn region ->
      held_since = Map.get(context.held_since, region)
      reported = MapSet.new(Map.get(served.reported, region, []))

      if region != context.primary and match?(%Date{}, held_since) and
           Date.diff(context.today, held_since) >= days and
           Enum.all?(window, &MapSet.member?(reported, &1)) and
           Map.get(totals, region, 0) == 0 and Map.get(today_hits, region, 0) == 0 and
           Enum.any?(serving, &(&1 != region and Map.get(totals, &1, 0) > 0)) do
        evidence =
          "zero_hits"
          |> served_evidence(days, 0, totals |> Map.values() |> Enum.sum(), 0)
          |> Map.merge(%{
            "reserved_gib" => Map.get(served.reserved_gib, region, 0),
            "reported_days" => days,
            "hits_per_active_day" => 0.0
          })

        {:retire, region, evidence}
      end
    end)
  end

  # A secondary retires once what it served stops paying for what it reserves.
  #
  # Both have to hold: a small share of the account's hits, and few hits for
  # the claim it holds. A share alone would let a busy primary veto every other
  # region, since a second site serving thousands of hits a day is a small share
  # of an account serving millions, and a rate alone would keep a region for an
  # account so busy that a rounding error of it clears any floor.
  #
  # Four weeks rather than a quarter: this reads the absence itself, on days
  # the region is known to have reported, and every week it waits is a week
  # the whole claim stays reserved for nothing.
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

  # A region cannot have spent the retirement window below the floor if the
  # account has not held it that long. Without this the two floors do not
  # actually straddle anything: a region opened on a fortnight's traffic has
  # served less than the retirement window's worth on the very day it opens,
  # so it would be given up again immediately and reopened by the same
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
