defmodule Tuist.Kura.ClaimSizing do
  @moduledoc """
  The pure decision core of automatic claim sizing: one account's day-grain
  storage rollups in, at most one recommended claim change out.

  The driving metric is shed age — how soon after being written an artifact
  was evicted under size pressure. One retention floor applies to every plan:
  content younger than it being shed means the claim is too small, and the
  ring span at eviction says how much history the current claim buys, which
  is what the grow target is projected from. The shrink signal is occupancy:
  an oversized ring never fills and never evicts, so evictions alone cannot
  show it.

  Plans do not get different sizing behaviour, only different room. Every
  account is measured against the same promise and confirmed on the same
  ladder; the ceiling is where a plan changes the answer, by bounding how
  far the claim may grow to keep that promise.

  Growth confirmation scales with severity rather than being a fixed wait.
  A confirmation window exists to rule out noise, and how much confirmation a
  reading needs depends on how bad it is: a ring shedding just under its
  floor is a marginal reading that could be a busy fortnight, while a ring
  shedding at a small fraction of its floor is unambiguous and costs the
  customer a rebuild of everything it drops in the meantime. The ladder is
  ordered shortest window first and the first qualifying rung decides.

  Severity is read two ways. The fractional arm tracks the floor, so
  recalibrating the promise moves the ladder with it. The absolute arm does
  not move: content that does not survive a working day is extreme however
  the floor is tuned, and the backstop should not drift when an operator
  changes what the floor means.

  The shortest rung is bought with volume rather than time, which is also
  what makes the ladder react faster the worse things get. A window counts
  daily rollup rows, and today's row is live — refreshed from the raw
  telemetry every sweep — so the rung that reads a single day reads a
  partial one, and the real latency floor is the hourly sweep rather than
  the calendar. What holds that rung back is evidence, not waiting: it asks
  for evicted bytes worth twice the whole claim. Because a ring turns over
  about once per span of content it holds, that proof accumulates at the
  rate the account is actually thrashing — a ring shedding at thirty
  minutes reaches it in about an hour, one shedding at eight hours takes
  most of a day — so response time falls out of severity without another
  rung to tune.

  Shrinking keeps its long single window on purpose: an oversized ring costs
  a reclaimable slot and nobody's build, so there is no urgency to trade
  confidence for.

  The rest is hysteresis: steps are clamped to at most double or halve, and
  targets are bounded by the per-plan ceiling and the validated minimum
  claim. Consecutive resizes are paced by the evidence itself rather than a
  flat cooldown: only days after the last resize count, both because they are
  the only days that measure the ring the current claim actually bought, and
  so each direction waits exactly its own window. Purity is what makes the
  shadow phase free: the sweep evaluates every account and stores the output,
  and acting on it is a separate decision.
  """

  alias Tuist.Kura.Regions

  @gibibyte 1024 * 1024 * 1024
  @seconds_per_day 86_400

  @default_policy %{
    # One promise for every plan: a cache should hold what was written to it
    # for at least this long before size pressure can take it. What a plan
    # buys is how far the claim may grow to keep that promise, not a weaker
    # version of it, so this is a single value and the ceiling below is where
    # the plans differ.
    retention_floor_days: 3,
    # Air and Pro share a ceiling: a free account's working set is not smaller
    # for being free, and capping it lower would have made the shared promise
    # unkeepable for exactly the accounts with the least room to absorb the
    # churn. What still separates them is where they start (Air at the
    # validated minimum) and how many confirmed steps it takes to get here.
    ceiling: %{air: "50Gi", pro: "50Gi", enterprise: "200Gi"},
    # The confirmation ladder, ordered shortest window first, so the most
    # severe rung a reading satisfies is the one that decides it.
    #
    # `shed_age_under` is either `{:seconds, n}` or `{:floor_fraction, f}`.
    # The fractional arm moves with the floor when the floor is recalibrated;
    # the absolute arm deliberately does not, so "gone before the next
    # morning's build" stays extreme whatever the floor is tuned to.
    #
    # `min_ring_turnover` is what buys the single-day rungs: evicted bytes
    # worth this many times the whole claim. Today's rollup is live, so those
    # rungs fire as soon as the loss proves itself, and cannot fire at all on
    # a thin day that only looks alarming.
    #
    # The required volume relaxes as the shed age gets worse, because the two
    # are evidence of the same thing and the shed age is the stronger half.
    # An hour of retention already rules out ordinary operation, so one full
    # ring lost confirms it; eight hours is bad but survivable long enough to
    # be a heavy week, so that rung wants two. Since a ring turns over about
    # once per span it holds, this is also what keeps the reaction time
    # proportional: an hour-old ring proves a single turnover in about an
    # hour, not in the two it would need at the lower rung.
    grow_windows: [
      %{shed_age_under: {:seconds, 3_600}, window_days: 1, min_ring_turnover: 1.0},
      %{shed_age_under: {:seconds, 28_800}, window_days: 1, min_ring_turnover: 2.0},
      %{shed_age_under: {:seconds, 28_800}, window_days: 2},
      %{shed_age_under: {:floor_fraction, 0.1}, window_days: 2},
      %{shed_age_under: {:floor_fraction, 0.34}, window_days: 5},
      %{shed_age_under: {:floor_fraction, 1.0}, window_days: 14}
    ],
    grow_headroom_factor: 1.25,
    shrink_window_days: 90,
    shrink_occupancy_percent: 40,
    shrink_target_occupancy_percent: 60,
    max_step_factor: 2.0
  }

  def default_policy, do: @default_policy

  @doc """
  Evaluates one account's rollups against the policy.

  Takes a context map with:

    * `:plan` - the account's sizing plan (`:air`, `:pro`, or `:enterprise`)
    * `:current_claim_size` - the claim the account's instances resolve today
    * `:rollups` - `Tuist.Kura.StorageRollup` rows (or maps with the same
      keys) covering the policy windows
    * `:last_resized_at` - when sizing last changed this account's claim, or
      `nil`; only rollups from days after it are evaluated
    * `:today` - the evaluation date

  Returns `{:grow | :shrink, recommended_claim_size, evidence}` or `:none`.
  Claims are account-scoped while telemetry is per region, so regions are
  evaluated independently and merged conservatively: any growing region grows
  the account to the largest target, and shrinking needs every region with
  data to agree.
  """
  def evaluate(context, policy \\ @default_policy) do
    case Regions.parse_storage_quantity(context.current_claim_size) do
      {:ok, current_bytes} ->
        context.rollups
        |> reject_pre_resize(context.last_resized_at)
        |> Enum.group_by(& &1.region)
        |> Enum.map(fn {region, rollups} ->
          evaluate_region(region, rollups, current_bytes, context, policy)
        end)
        |> merge_verdicts(current_bytes, context, policy)

      :error ->
        :none
    end
  end

  # Only days after the last resize can qualify a window: earlier days measured
  # the ring the previous claim bought, so their spans and occupancy describe a
  # budget that no longer exists. This is also what paces consecutive resizes,
  # each direction by exactly its own window instead of a flat cooldown. The
  # resize day itself is excluded because its rollup mixes both rings.
  defp reject_pre_resize(rollups, nil), do: rollups

  defp reject_pre_resize(rollups, last_resized_at) do
    resize_date = DateTime.to_date(last_resized_at)
    Enum.reject(rollups, &(Date.compare(&1.date, resize_date) != :gt))
  end

  defp evaluate_region(region, rollups, current_bytes, context, policy) do
    by_date = Map.new(rollups, &{&1.date, &1})
    floor_seconds = policy.retention_floor_days * @seconds_per_day

    cond do
      grow = grow_verdict(by_date, floor_seconds, current_bytes, context, policy) ->
        {target_bytes, evidence} = grow
        {:grow, region, target_bytes, evidence}

      window = qualifying_window(by_date, context.today, policy.shrink_window_days, &shrink_day?(&1, policy)) ->
        {:shrink, region, shrink_target_bytes(window, policy), shrink_evidence(window, policy)}

      true ->
        {:none, region}
    end
  end

  # The severity ladder: the first rung whose window is fully satisfied wins,
  # and the rungs are ordered shortest window first, so the worse a ring's
  # shedding is the sooner it can act. A badly undersized claim is corrected
  # in a day or two rather than made to serve out a fortnight of rebuilding
  # content it just evicted.
  defp grow_verdict(by_date, floor_seconds, current_bytes, context, policy) do
    Enum.find_value(policy.grow_windows, fn rung ->
      threshold_seconds = shed_age_threshold(rung.shed_age_under, floor_seconds)

      with window when not is_nil(window) <-
             qualifying_window(by_date, context.today, rung.window_days, &grow_day?(&1, threshold_seconds)),
           true <- ring_turnover(window, current_bytes) >= Map.get(rung, :min_ring_turnover, 0.0) do
        {grow_target_bytes(window, current_bytes, floor_seconds, policy),
         grow_evidence(window, floor_seconds, threshold_seconds, current_bytes)}
      else
        _ -> nil
      end
    end)
  end

  defp shed_age_threshold({:seconds, seconds}, _floor_seconds), do: seconds
  defp shed_age_threshold({:floor_fraction, fraction}, floor_seconds), do: round(floor_seconds * fraction)

  # How many times over the account evicted its whole claim across the window.
  # Volume rather than elapsed time, so a rung can be satisfied by how much
  # cache was actually lost instead of by how long we waited to count it.
  defp ring_turnover(_window, current_bytes) when current_bytes <= 0, do: 0.0

  defp ring_turnover(window, current_bytes) do
    window |> Enum.map(& &1.evicted_bytes) |> Enum.sum() |> Kernel./(current_bytes)
  end

  # A day argues for growth when the ring rotated under size pressure and the
  # median evicted segment held content younger than the tier's threshold.
  # Evictions only happen at a full ring, so no separate occupancy gate is
  # needed on this side. Backfilled content cannot fake this: the shed age is
  # measured from the content's own version, so a ring filled with a peer's
  # old artifacts reports old shed ages, not young ones.
  defp grow_day?(rollup, threshold_seconds) do
    rollup.eviction_count > 0 and rollup.median_shed_age_seconds != nil and
      rollup.median_shed_age_seconds < threshold_seconds
  end

  # A day argues for shrinking when the instance reported occupancy all day
  # below the threshold and nothing evicted. Days without snapshots (the
  # instance wasn't running) break the streak: absence of evidence is not a
  # small working set.
  defp shrink_day?(rollup, policy) do
    rollup.snapshot_count > 0 and rollup.eviction_count == 0 and
      rollup.max_occupancy_percent != nil and
      rollup.max_occupancy_percent < policy.shrink_occupancy_percent
  end

  # The most recent `window_days` consecutive calendar days, all qualifying.
  # The window may end today or yesterday: today's partial rollup counts when
  # it already qualifies, and is not held against an account when it does not
  # yet, so a streak is never broken by the hour of the day the sweep runs.
  defp qualifying_window(by_date, today, window_days, qualifies?) do
    Enum.find_value([today, Date.add(today, -1)], fn end_day ->
      window =
        for offset <- (window_days - 1)..0//-1 do
          Map.get(by_date, Date.add(end_day, -offset))
        end

      if Enum.all?(window, &(&1 != nil and qualifies?.(&1))), do: window
    end)
  end

  # The ring span at eviction is the retention the current claim buys, so the
  # claim that buys the floor is a proportional projection from it, padded
  # with headroom so a correct resize does not land exactly on the boundary
  # it is escaping.
  defp grow_target_bytes(window, current_bytes, floor_seconds, policy) do
    span_seconds = window |> Enum.map(& &1.median_ring_span_seconds) |> median() |> max(1)

    projected = current_bytes * (floor_seconds / span_seconds) * policy.grow_headroom_factor

    projected
    |> min(current_bytes * policy.max_step_factor)
    |> max(current_bytes)
    |> round()
  end

  # Size the claim so the window's peak working set sits at the target
  # occupancy, clamped so one step never less than halves the claim.
  defp shrink_target_bytes(window, policy) do
    peak_bytes =
      window
      |> Enum.map(&(&1.max_live_segment_bytes || 0))
      |> Enum.max()

    round(peak_bytes * 100 / policy.shrink_target_occupancy_percent)
  end

  defp merge_verdicts(verdicts, current_bytes, context, policy) do
    grows = for {:grow, region, target, evidence} <- verdicts, do: {region, target, evidence}
    shrinks = for {:shrink, region, target, evidence} <- verdicts, do: {region, target, evidence}

    cond do
      grows != [] ->
        {region, target, evidence} = Enum.max_by(grows, fn {_region, target, _evidence} -> target end)
        finalize(:grow, region, target, evidence, current_bytes, context, policy)

      shrinks != [] and length(shrinks) == length(verdicts) ->
        {region, target, evidence} = Enum.max_by(shrinks, fn {_region, target, _evidence} -> target end)
        finalize(:shrink, region, target, evidence, current_bytes, context, policy)

      true ->
        :none
    end
  end

  defp finalize(direction, region, target_bytes, evidence, current_bytes, context, policy) do
    target_bytes
    |> clamp(direction, current_bytes, context.plan, policy)
    |> case do
      ^current_bytes ->
        :none

      bytes ->
        recommended = to_gibibyte_quantity(bytes)

        if quantity_bytes(recommended) == current_bytes do
          :none
        else
          {direction, recommended, Map.put(evidence, "region", region)}
        end
    end
  end

  defp clamp(target_bytes, :grow, current_bytes, plan, policy) do
    target_bytes
    |> min(quantity_bytes(ceiling(plan, policy)))
    |> max(current_bytes)
  end

  defp clamp(target_bytes, :shrink, current_bytes, _plan, policy) do
    target_bytes
    |> max(round(current_bytes / policy.max_step_factor))
    |> max(quantity_bytes(Regions.minimum_storage_claim()))
    |> min(current_bytes)
  end

  defp grow_evidence(window, floor_seconds, threshold_seconds, current_bytes) do
    %{
      "signal" => "shed_age_below_retention_floor",
      "window_days" => length(window),
      "retention_floor_seconds" => floor_seconds,
      # What the window had to hold under to qualify at the rung that fired,
      # so an operator reading a one-day proposal can see it was the severity
      # that shortened it rather than a weakened rule.
      "qualifying_threshold_seconds" => threshold_seconds,
      "median_shed_age_seconds" => window |> Enum.map(& &1.median_shed_age_seconds) |> median(),
      "median_ring_span_seconds" => window |> Enum.map(& &1.median_ring_span_seconds) |> median(),
      "evicted_bytes" => window |> Enum.map(& &1.evicted_bytes) |> Enum.sum(),
      "ring_turnover" => window |> ring_turnover(current_bytes) |> Float.round(1)
    }
  end

  defp shrink_evidence(window, policy) do
    %{
      "signal" => "occupancy_below_threshold",
      "window_days" => length(window),
      "occupancy_threshold_percent" => policy.shrink_occupancy_percent,
      "max_occupancy_percent" => window |> Enum.map(& &1.max_occupancy_percent) |> Enum.max(),
      "peak_live_segment_bytes" => window |> Enum.map(&(&1.max_live_segment_bytes || 0)) |> Enum.max()
    }
  end

  # Plans resolve exactly like Tuist.Kura.Regions.storage_profile/1: the paid
  # plans explicitly, everything else at Air's values.
  # The one place a plan changes the outcome: how far the shared promise may
  # be funded. Resolved exactly like `Tuist.Kura.Regions.storage_profile/1`,
  # the paid plans explicitly and everything else at Air's.
  defp ceiling(plan, policy), do: Map.get(policy.ceiling, plan, policy.ceiling.air)

  defp quantity_bytes(quantity) do
    {:ok, bytes} = Regions.parse_storage_quantity(quantity)
    bytes
  end

  # Claims render as whole gibibytes, rounded up so a target is never
  # under-provisioned by the rounding itself.
  defp to_gibibyte_quantity(bytes) do
    "#{max(div(bytes + @gibibyte - 1, @gibibyte), 1)}Gi"
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = values |> Enum.reject(&is_nil/1) |> Enum.sort()

    case length(sorted) do
      0 -> nil
      count when rem(count, 2) == 1 -> Enum.at(sorted, div(count, 2))
      count -> div(Enum.at(sorted, div(count, 2) - 1) + Enum.at(sorted, div(count, 2)), 2)
    end
  end
end
