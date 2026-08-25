defmodule Tuist.Kura.ClaimSizing do
  @moduledoc """
  The pure decision core of automatic claim sizing: one account's day-grain
  storage rollups in, at most one recommended claim change out.

  The driving metric is shed age — how soon after being written an artifact
  was evicted under size pressure. Each plan carries a retention floor the
  ring must hold: content younger than the floor being shed means the claim
  is too small, and the ring span at eviction says how much history the
  current claim buys, which is what the grow target is projected from. The
  shrink signal is occupancy: an oversized ring never fills and never evicts,
  so evictions alone cannot show it.

  Everything here is policy configuration with hysteresis: growth needs a
  sustained streak of churning days, shrinking needs a much longer streak of
  near-empty days, steps are clamped to at most double or halve, targets are
  bounded by the per-plan ceiling and the validated minimum claim, and a
  cooldown spaces consecutive resizes. Purity is what makes the shadow phase
  free: the sweep evaluates every account and stores the output, and acting
  on it is a separate decision.
  """

  alias Tuist.Kura.Regions

  @gibibyte 1024 * 1024 * 1024
  @seconds_per_day 86_400

  @default_policy %{
    retention_floor_days: %{air: 1, pro: 3, enterprise: 3},
    ceiling: %{air: "16Gi", pro: "50Gi", enterprise: "50Gi"},
    grow_window_days: 14,
    grow_headroom_factor: 1.25,
    shrink_window_days: 90,
    shrink_occupancy_percent: 40,
    shrink_target_occupancy_percent: 60,
    min_days_between_resizes: 30,
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
      `nil`
    * `:today` - the evaluation date

  Returns `{:grow | :shrink, recommended_claim_size, evidence}` or `:none`.
  Claims are account-scoped while telemetry is per region, so regions are
  evaluated independently and merged conservatively: any growing region grows
  the account to the largest target, and shrinking needs every region with
  data to agree.
  """
  def evaluate(context, policy \\ @default_policy) do
    with {:ok, current_bytes} <- Regions.parse_storage_quantity(context.current_claim_size),
         false <- in_cooldown?(context, policy) do
      context.rollups
      |> Enum.group_by(& &1.region)
      |> Enum.map(fn {region, rollups} ->
        evaluate_region(region, rollups, current_bytes, context, policy)
      end)
      |> merge_verdicts(current_bytes, context, policy)
    else
      _ -> :none
    end
  end

  defp in_cooldown?(%{last_resized_at: nil}, _policy), do: false

  defp in_cooldown?(%{last_resized_at: last_resized_at, today: today}, policy) do
    Date.diff(today, DateTime.to_date(last_resized_at)) < policy.min_days_between_resizes
  end

  defp evaluate_region(region, rollups, current_bytes, context, policy) do
    by_date = Map.new(rollups, &{&1.date, &1})
    floor_seconds = retention_floor_days(context.plan, policy) * @seconds_per_day

    cond do
      window = qualifying_window(by_date, context.today, policy.grow_window_days, &grow_day?(&1, floor_seconds)) ->
        {:grow, region, grow_target_bytes(window, current_bytes, floor_seconds, policy),
         grow_evidence(window, floor_seconds)}

      window = qualifying_window(by_date, context.today, policy.shrink_window_days, &shrink_day?(&1, policy)) ->
        {:shrink, region, shrink_target_bytes(window, policy), shrink_evidence(window, policy)}

      true ->
        {:none, region}
    end
  end

  # A day argues for growth when the ring rotated under size pressure and the
  # median evicted segment held content younger than the plan's retention
  # floor. Evictions only happen at a full ring, so no separate occupancy gate
  # is needed on this side.
  defp grow_day?(rollup, floor_seconds) do
    rollup.eviction_count > 0 and rollup.median_shed_age_seconds != nil and
      rollup.median_shed_age_seconds < floor_seconds
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

  defp grow_evidence(window, floor_seconds) do
    %{
      "signal" => "shed_age_below_retention_floor",
      "window_days" => length(window),
      "retention_floor_seconds" => floor_seconds,
      "median_shed_age_seconds" => window |> Enum.map(& &1.median_shed_age_seconds) |> median(),
      "median_ring_span_seconds" => window |> Enum.map(& &1.median_ring_span_seconds) |> median(),
      "evicted_bytes" => window |> Enum.map(& &1.evicted_bytes) |> Enum.sum()
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
  defp retention_floor_days(plan, policy), do: Map.get(policy.retention_floor_days, plan, policy.retention_floor_days.air)

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
