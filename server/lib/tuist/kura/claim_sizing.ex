defmodule Tuist.Kura.ClaimSizing do
  @moduledoc """
  Decides one account's disk claim from its storage rollups. Pure: rollups in,
  at most one recommended change out.

  Growth is driven by shed age (how soon after being written content was
  evicted), shrinking by occupancy, because an oversized ring never evicts and
  so produces no shed age at all. Confirmation scales with severity: the worse
  the shedding, the shorter the window, and the shortest rungs are bought with
  evicted volume rather than elapsed time.

  Windows count rollup rows, one row being one UTC day per account-region.
  Today's row is live, so a one-row window can be satisfied in minutes. Rows
  are the mechanism; give any reader a duration.
  """

  alias Tuist.Kura.Regions

  @gibibyte 1024 * 1024 * 1024
  @seconds_per_day 86_400

  @default_policy %{
    retention_floor_days: 3,
    ceiling: %{air: "64Gi", pro: "64Gi", enterprise: "256Gi"},
    # Ordered shortest window first; the first rung a reading satisfies wins.
    # The absolute arm does not move when the floor is recalibrated.
    grow_windows: [
      %{shed_age_under: {:seconds, 3_600}, window_days: 1, min_ring_turnover: 1.0},
      %{shed_age_under: {:seconds, 28_800}, window_days: 1, min_ring_turnover: 2.0},
      %{shed_age_under: {:seconds, 28_800}, window_days: 2},
      %{shed_age_under: {:floor_fraction, 0.1}, window_days: 2},
      %{shed_age_under: {:floor_fraction, 0.34}, window_days: 5},
      %{shed_age_under: {:floor_fraction, 1.0}, window_days: 14}
    ],
    grow_headroom_factor: 1.25,
    shrink_window_days: 30,
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

  # Days up to and including a resize measured the previous claim's ring.
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

  defp ring_turnover(_window, current_bytes) when current_bytes <= 0, do: 0.0

  defp ring_turnover(window, current_bytes) do
    window |> Enum.map(& &1.evicted_bytes) |> Enum.sum() |> Kernel./(current_bytes)
  end

  # Backfill cannot fake this: shed age is measured from the content's own
  # version, so a ring filled from a peer reports old ages, not young ones.
  defp grow_day?(rollup, threshold_seconds) do
    rollup.eviction_count > 0 and rollup.median_shed_age_seconds != nil and
      rollup.median_shed_age_seconds < threshold_seconds
  end

  # A day without snapshots breaks the streak: absence of evidence is not a
  # small working set.
  defp shrink_day?(rollup, policy) do
    rollup.snapshot_count > 0 and rollup.eviction_count == 0 and
      rollup.max_occupancy_percent != nil and
      rollup.max_occupancy_percent < policy.shrink_occupancy_percent
  end

  # Ends today or yesterday, so the hour the sweep runs never breaks a streak.
  defp qualifying_window(by_date, today, window_days, qualifies?) do
    Enum.find_value([today, Date.add(today, -1)], fn end_day ->
      window =
        for offset <- (window_days - 1)..0//-1 do
          Map.get(by_date, Date.add(end_day, -offset))
        end

      if Enum.all?(window, &(&1 != nil and qualifies?.(&1))), do: window
    end)
  end

  # Projected from the retention the current claim buys, plus headroom so a
  # correct resize does not land on the boundary it is escaping.
  defp grow_target_bytes(window, current_bytes, floor_seconds, policy) do
    span_seconds = window |> Enum.map(& &1.median_ring_span_seconds) |> median() |> max(1)

    projected = current_bytes * (floor_seconds / span_seconds) * policy.grow_headroom_factor

    projected
    |> min(current_bytes * policy.max_step_factor)
    |> max(current_bytes)
    |> round()
  end

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

  # The one place a plan changes the outcome.
  defp ceiling(plan, policy), do: Map.get(policy.ceiling, plan, policy.ceiling.air)

  defp quantity_bytes(quantity) do
    {:ok, bytes} = Regions.parse_storage_quantity(quantity)
    bytes
  end

  # Rounded up so a target is never under-provisioned by the rounding.
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
