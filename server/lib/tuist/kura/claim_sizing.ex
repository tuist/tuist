defmodule Tuist.Kura.ClaimSizing do
  @moduledoc """
  Decides one account's disk claim from its storage rollups. Pure: rollups in,
  at most one recommended change out.

  Growth is driven by shed age (how soon after being written content was
  evicted). Confirmation scales with severity: the worse the shedding, the
  shorter the window, and a tier's window can be bought down with the volume
  the ring cycled in place of elapsed time. The step a reading may take scales
  with the confirmation behind it. A step clamped below its own projection lets
  the next one confirm on a single day of the resized ring that cycled at least
  a ring, within each rung's own window of the resize.

  Shrinking has two signals. A ring that never fills produces no shed age at
  all, so it shrinks on occupancy. A ring that rotates shrinks on retention
  once every day of a month kept its content for three retention floors: it
  lands where the floor plus the growth headroom would be kept, at most halving
  the claim in one step and never under the plan's starting claim. Both are
  slower to confirm than any growth, because a shrink that overshoots costs a
  rebuild to undo and one that waits costs only disk.

  Moderate excess retention can correct sooner: fourteen complete days,
  seven active eviction days and two ring budgets of turnover permit at most
  a quarter off the claim. Known idle time is discounted from retention, and
  every resize restarts the evidence window. Corrections smaller than a tenth
  of the account claim are withheld to avoid rebuilding for rounding noise.

  Each region is measured against the claim its own instances hold, since that
  is the ring its telemetry describes. The account keeps one claim, the largest
  any region needs, so a region pinned under it that runs short is raised to it
  even when its own ring asks for less.

  Windows count rollup rows, one row being one UTC day per account-region.
  Today's row is live, so a one-row window can be satisfied in minutes. Rows
  are the mechanism; give any reader a duration.

  A day that misses a growth threshold because the account was idle does not
  break the streak: a day it wrote nothing to a full ring, one it barely wrote
  to next to such a day, or one with either inside its shed age, is passed
  over. A day that meets the threshold always counts, and an ordinary day of a
  right-sized ring still breaks the streak. Shrinking still needs every day in
  its window.
  """

  alias Tuist.Kura.Regions

  @gibibyte 1024 * 1024 * 1024
  @seconds_per_day 86_400

  @default_policy %{
    retention_floor_days: 3,
    ceiling: %{air: "64Gi", pro: "64Gi", enterprise: "256Gi"},
    # Ordered shortest window first; the first rung a reading satisfies wins.
    # The absolute arm does not move when the floor is recalibrated. A tier
    # appears twice where volume can stand in for elapsed time: the ring the
    # account cycled is evidence the same reading held all day. Turnover counts
    # rings across the whole window, so two over two days is one a day.
    grow_windows: [
      %{shed_age_under: {:seconds, 3_600}, window_days: 1, min_ring_turnover: 1.0},
      %{shed_age_under: {:seconds, 28_800}, window_days: 1, min_ring_turnover: 2.0},
      %{shed_age_under: {:seconds, 28_800}, window_days: 2},
      %{shed_age_under: {:floor_fraction, 0.1}, window_days: 2},
      %{shed_age_under: {:floor_fraction, 0.34}, window_days: 2, min_ring_turnover: 2.0},
      %{shed_age_under: {:floor_fraction, 0.34}, window_days: 5},
      %{shed_age_under: {:floor_fraction, 1.0}, window_days: 14}
    ],
    grow_headroom_factor: 1.25,
    shrink_window_days: 30,
    shrink_occupancy_percent: 40,
    shrink_target_occupancy_percent: 60,
    # Three floors, so the halving one step may take still leaves a ring
    # holding 1.5 floors, clear of the 1.25 growth projects to and twice the
    # floor the longest growth rung reads.
    retention_shrink_window_days: 30,
    retention_shrink_floor_multiple: 3,
    retention_correction_window_days: 14,
    retention_correction_min_active_days: 7,
    retention_correction_min_ring_turnover: 2.0,
    retention_correction_floor_multiple: 1.5,
    retention_correction_max_reduction_percent: 25,
    retention_correction_min_reduction_percent: 10,
    max_step_factor: 2.0,
    max_confirmed_step_factor: 4.0
  }

  def default_policy, do: @default_policy

  @doc """
  How many days before today a verdict can read: a growth window collects its
  days and may pass over as many again, and each shrink window reads its own.
  """
  def lookback_days(policy \\ @default_policy) do
    Enum.max([
      2 * passable_days(policy),
      policy.shrink_window_days,
      policy.retention_shrink_window_days,
      policy.retention_correction_window_days
    ])
  end

  @doc """
  Evaluates one account's rollups against the policy.

  Takes a context map with:

    * `:plan` - the account's sizing plan (`:air`, `:pro`, or `:enterprise`)
    * `:current_claim_size` - the claim the account's instances resolve today
    * `:region_claim_sizes` - optional, the claim pinned in each region, by
      region; a region missing from it is measured against
      `:current_claim_size`
    * `:rollups` - `Tuist.Kura.StorageRollup` rows (or maps with the same
      keys) covering the policy windows
    * `:last_resized_at` - when sizing last changed this account's claim, or
      `nil`; only rollups from days after it are evaluated
    * `:capped_resize_from` - the claim the last applied resize grew from when
      that growth was capped (see `capped_growth?/2`), or `nil`
    * `:today` - the evaluation date

  Returns `{:grow | :shrink, recommended_claim_size, evidence}` or `:none`.
  Claims are account-scoped while telemetry is per region, so regions are
  evaluated independently and merged conservatively: any growing region grows
  the account to the largest target, and shrinking needs every region with
  data to agree. A growth whose target the account's claim already covers
  recommends that claim, to raise the region pinned under it.
  """
  def evaluate(context, policy \\ @default_policy) do
    case Regions.parse_storage_quantity(context.current_claim_size) do
      {:ok, current_bytes} ->
        context.rollups
        |> reject_pre_resize(context.last_resized_at)
        |> Enum.group_by(& &1.region)
        |> Enum.map(fn {region, rollups} ->
          evaluate_region(region, rollups, region_claim(context, region, current_bytes), context, policy)
        end)
        |> merge_verdicts(current_bytes, context, policy)

      :error ->
        :none
    end
  end

  @doc """
  Whether an applied growth landed below the claim its own evidence projected
  from the ring it measured, because the step bound or the plan ceiling
  clamped it.
  """
  def capped_growth?(proposal, policy \\ @default_policy)

  def capped_growth?(
        %{direction: :grow, current_claim_size: current, recommended_claim_size: recommended, evidence: evidence},
        policy
      ) do
    with {:ok, claim_bytes} <- Regions.parse_storage_quantity(Map.get(evidence, "region_claim_size", current)),
         {:ok, recommended_bytes} <- Regions.parse_storage_quantity(recommended),
         %{"retention_floor_seconds" => floor_seconds, "median_ring_span_seconds" => span_seconds}
         when is_number(floor_seconds) and is_number(span_seconds) <- evidence do
      recommended_bytes < round(projected_bytes(claim_bytes, floor_seconds, span_seconds, policy))
    else
      _ -> false
    end
  end

  def capped_growth?(_proposal, _policy), do: false

  # Days up to and including a resize measured the previous claim's ring.
  defp reject_pre_resize(rollups, nil), do: rollups

  defp reject_pre_resize(rollups, last_resized_at) do
    resize_date = DateTime.to_date(last_resized_at)
    Enum.reject(rollups, &(Date.compare(&1.date, resize_date) != :gt))
  end

  # The claim pinned on the region's instances funds the ring its telemetry
  # measured, so it is what that ring's reading scales: read against the
  # account's largest pin, a 16Gi region's shortfall is sized as if it ran
  # 50Gi. A region with no pin renders the account's claim.
  defp region_claim(context, region, current_bytes) do
    with claim when is_binary(claim) <- context |> Map.get(:region_claim_sizes, %{}) |> Map.get(region),
         {:ok, claim_bytes} <- Regions.parse_storage_quantity(claim) do
      {claim, claim_bytes}
    else
      _ -> {context.current_claim_size, current_bytes}
    end
  end

  defp evaluate_region(region, rollups, {claim, claim_bytes}, context, policy) do
    by_date = Map.new(rollups, &{&1.date, &1})
    floor_seconds = policy.retention_floor_days * @seconds_per_day

    cond do
      grow = grow_verdict(by_date, floor_seconds, claim_bytes, context, policy) ->
        {target_bytes, evidence} = grow
        {:grow, region, target_bytes, claim_bytes, Map.put(evidence, "region_claim_size", claim)}

      window = qualifying_window(by_date, context.today, policy.shrink_window_days, 0, &shrink_standing(&1, policy)) ->
        {:shrink, :occupancy, region, shrink_target_bytes(window, policy), claim_bytes, shrink_evidence(window, policy)}

      retention = retention_verdict(by_date, floor_seconds, claim_bytes, context, policy) ->
        {target_bytes, evidence} = retention
        {:shrink, :retention, region, target_bytes, claim_bytes, Map.put(evidence, "region_claim_size", claim)}

      correction = retention_correction_verdict(by_date, floor_seconds, claim_bytes, context, policy) ->
        {target_bytes, evidence} = correction

        {:shrink, :retention_correction, region, target_bytes, claim_bytes, Map.put(evidence, "region_claim_size", claim)}

      true ->
        {:none, region}
    end
  end

  defp grow_verdict(by_date, floor_seconds, claim_bytes, context, policy) do
    idle_dates = idle_dates(by_date, policy)

    rung_verdict(policy.grow_windows, by_date, idle_dates, floor_seconds, claim_bytes, context, policy) ||
      capped_resize_verdict(by_date, idle_dates, floor_seconds, claim_bytes, context, policy)
  end

  defp rung_verdict(rungs, by_date, idle_dates, floor_seconds, claim_bytes, context, policy) do
    Enum.find_value(rungs, fn rung ->
      threshold_seconds = shed_age_threshold(rung.shed_age_under, floor_seconds)
      standing = &grow_standing(&1, idle_dates, threshold_seconds)

      with window when not is_nil(window) <-
             qualifying_window(by_date, context.today, rung.window_days, passable_days(policy), standing),
           true <- turnover_cleared?(window, rung) do
        {grow_target_bytes(window, claim_bytes, floor_seconds, rung, policy),
         grow_evidence(window, floor_seconds, threshold_seconds)}
      else
        _ -> nil
      end
    end)
  end

  # The capped step's evidence already proved the ring short, so a rung
  # confirms on one day of the resized ring, at the one-day bound, until its
  # own window could have run since the resize. That day pays in volume, as
  # the ladder's own one-day rungs do: a rebuilt ring sheds nothing older than
  # itself, so shed age alone cannot tell a short ring from a young one.
  defp capped_resize_verdict(_by_date, _idle_dates, _floor_seconds, _claim_bytes, %{capped_resize_from: nil}, _policy),
    do: nil

  defp capped_resize_verdict(by_date, idle_dates, floor_seconds, claim_bytes, context, policy) do
    previous_bytes = quantity_bytes(context.capped_resize_from)
    resize_date = DateTime.to_date(context.last_resized_at)
    resized = Map.filter(by_date, fn {_date, rollup} -> resized_ring?(rollup, previous_bytes) end)
    one_day_turnover = one_day_ring_turnover(policy)

    Enum.find_value(policy.grow_windows, fn rung ->
      horizon = Date.add(resize_date, rung.window_days)
      days = Map.filter(resized, fn {date, _rollup} -> Date.compare(date, horizon) != :gt end)
      turnover = max(Map.get(rung, :min_ring_turnover, 0), one_day_turnover)
      one_day_rung = Map.merge(rung, %{window_days: 1, min_ring_turnover: turnover})

      case rung_verdict([one_day_rung], days, idle_dates, floor_seconds, claim_bytes, context, policy) do
        nil -> nil
        {target_bytes, evidence} -> {target_bytes, Map.put(evidence, "after_capped_resize", true)}
      end
    end)
  end

  defp one_day_ring_turnover(policy) do
    policy.grow_windows
    |> Enum.filter(&(&1.window_days == 1))
    |> Enum.map(& &1.min_ring_turnover)
    |> Enum.min()
  end

  # A claim funds a ring smaller than itself, so the day's smallest ring clears
  # the replaced claim only when no instance ran the old ring that day.
  defp resized_ring?(%{min_ring_budget_bytes: ring_bytes}, previous_bytes) do
    is_integer(ring_bytes) and ring_bytes > previous_bytes
  end

  defp shed_age_threshold({:seconds, seconds}, _floor_seconds), do: seconds
  defp shed_age_threshold({:floor_fraction, fraction}, floor_seconds), do: round(floor_seconds * fraction)

  # An unmeasured ring is no denominator, so a rung that asks for turnover
  # goes unproven rather than falling back to the claim: the claim also funds
  # upload staging, a spare segment and the index, so it is materially larger
  # than the ring it pays for and would read turnover low on every account.
  defp turnover_cleared?(window, rung) do
    case {Map.get(rung, :min_ring_turnover), ring_turnover(window)} do
      {nil, _turnover} -> true
      {_minimum, nil} -> false
      {minimum, turnover} -> turnover >= minimum
    end
  end

  defp ring_turnover(window) do
    case ring_budget_bytes(window) do
      nil -> nil
      budget_bytes -> window |> Enum.map(& &1.evicted_bytes) |> Enum.sum() |> Kernel./(budget_bytes)
    end
  end

  # The ring the nodes reported running, taken at its smallest across the
  # window. A window never spans a resize, so the days normally agree; when
  # they do not, every byte in the sum went out against a ring at least this
  # small.
  defp ring_budget_bytes(window) do
    window
    |> Enum.map(& &1.last_ring_budget_bytes)
    |> Enum.reject(&(is_nil(&1) or &1 <= 0))
    |> Enum.min(fn -> nil end)
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

  # A live day only adds evictions and raises its peak, so today's row that has
  # already evicted or filled past the line contradicts the shrink however
  # early in the day it is.
  defp shrink_standing(nil, _policy), do: :breaks

  defp shrink_standing(rollup, policy) do
    cond do
      shrink_day?(rollup, policy) -> :qualifies
      rollup.eviction_count > 0 -> :contradicts
      (rollup.max_occupancy_percent || 0) >= policy.shrink_occupancy_percent -> :contradicts
      true -> :breaks
    end
  end

  # Every day of the window kept what it shed past the threshold, or shed
  # nothing at all. The claim is projected from the shortest span any of those
  # days measured, because it has to keep the floor on that day too. A window
  # that shed nothing measured no span, and a ring that fills without rotating
  # is not evidence of how much less it could hold.
  defp retention_verdict(by_date, floor_seconds, claim_bytes, context, policy) do
    threshold_seconds = floor_seconds * policy.retention_shrink_floor_multiple
    standing = &retention_standing(&1, threshold_seconds)

    with window when is_list(window) <-
           qualifying_window(by_date, context.today, policy.retention_shrink_window_days, 0, standing),
         span_seconds when is_integer(span_seconds) <- shortest(window, :median_ring_span_seconds) do
      {round(projected_bytes(claim_bytes, floor_seconds, span_seconds, policy)),
       retention_evidence(window, floor_seconds, threshold_seconds)}
    else
      _ -> nil
    end
  end

  # Today's row that has already shed content younger than the threshold
  # contradicts the shrink. Its median can still rise before the day ends, but
  # vetoing costs a shrink a day at most, while passing over it would discard
  # the only reading against it. One that has shed nothing young yet, or has
  # not sent its first snapshot, has measured nothing and is passed over.
  defp retention_standing(nil, _threshold_seconds), do: :breaks

  defp retention_standing(rollup, threshold_seconds) do
    cond do
      shed_young?(rollup, threshold_seconds) -> :contradicts
      retention_day?(rollup) -> :qualifies
      true -> :breaks
    end
  end

  defp shed_young?(rollup, threshold_seconds) do
    rollup.eviction_count > 0 and rollup.median_shed_age_seconds != nil and
      rollup.median_shed_age_seconds < threshold_seconds
  end

  # A day without snapshots breaks the window here too. Unlike growth, no
  # earlier day is passed over: one that shed content younger than the
  # threshold is the evidence against shrinking, however idle the days around
  # it were.
  defp retention_day?(rollup) do
    rollup.snapshot_count > 0 and (rollup.eviction_count == 0 or rollup.median_shed_age_seconds != nil)
  end

  defp retention_correction_verdict(by_date, floor_seconds, claim_bytes, context, policy) do
    threshold_seconds = round(floor_seconds * policy.retention_correction_floor_multiple)
    idle_dates = idle_dates(by_date, policy)
    adjusted = Map.new(by_date, fn {date, row} -> {date, discount_idle_time(row, idle_dates)} end)

    standing = fn row ->
      if correction_contradicted?(row, threshold_seconds),
        do: :contradicts,
        else: retention_standing(row, threshold_seconds)
    end

    with false <- correction_contradicted?(Map.get(adjusted, context.today), threshold_seconds),
         window when is_list(window) <-
           collect_window(
             adjusted,
             Date.add(context.today, -1),
             policy.retention_correction_window_days,
             0,
             standing,
             []
           ),
         active = Enum.filter(window, &(&1.eviction_count > 0 and not MapSet.member?(idle_dates, &1.date))),
         true <- length(active) >= policy.retention_correction_min_active_days,
         turnover when is_number(turnover) <- correction_turnover(active),
         true <- turnover >= policy.retention_correction_min_ring_turnover,
         true <- Enum.all?(active, &is_integer(&1.median_ring_span_seconds)),
         span_seconds when is_integer(span_seconds) <- shortest(active, :median_ring_span_seconds) do
      evidence =
        active
        |> retention_evidence(floor_seconds, threshold_seconds)
        |> Map.merge(%{
          "window_days" => length(window),
          "active_days" => length(active),
          "ring_turnover" => round_turnover(turnover),
          "ring_budget_bytes" => active |> Enum.map(& &1.last_ring_budget_bytes) |> Enum.max(),
          "idle_time_discounted" => true,
          "max_reduction_percent" => policy.retention_correction_max_reduction_percent
        })

      {round(projected_bytes(claim_bytes, floor_seconds, span_seconds, policy)), evidence}
    else
      _ -> nil
    end
  end

  defp correction_contradicted?(nil, _threshold_seconds), do: false

  defp correction_contradicted?(row, threshold_seconds) do
    row.eviction_count > 0 and
      (not is_integer(row.median_shed_age_seconds) or not is_integer(row.median_ring_span_seconds) or
         row.median_shed_age_seconds < threshold_seconds or row.median_ring_span_seconds < threshold_seconds)
  end

  # The first and last date of an eviction's age are partial. Only whole
  # intervening days known to be idle can be subtracted from the measurement.
  defp discount_idle_time(row, idle_dates) do
    Enum.reduce([:median_shed_age_seconds, :median_ring_span_seconds], row, fn key, adjusted ->
      case Map.fetch!(row, key) do
        seconds when is_integer(seconds) ->
          whole_days = max(div(seconds, @seconds_per_day) - 1, 0)
          idle_days = Enum.count(idle_dates, &(Date.diff(row.date, &1) in 1..whole_days//1))
          Map.put(adjusted, key, seconds - idle_days * @seconds_per_day)

        _ ->
          adjusted
      end
    end)
  end

  # A changing or missing budget must not make a quiet interval look like
  # representative turnover. Use the largest measured budget, unlike growth.
  defp correction_turnover(active) do
    budgets = Enum.map(active, & &1.last_ring_budget_bytes)

    if Enum.all?(budgets, &(is_integer(&1) and &1 > 0)) do
      Enum.sum(Enum.map(active, & &1.evicted_bytes)) / Enum.max(budgets)
    end
  end

  # Idle time can only lengthen a shed age, so a day under the threshold
  # qualifies however little it evicted, today's live row included. A day over
  # it is passed over when it was idle itself or an idle day sits inside its
  # shed age: the gap may be all it measured.
  defp grow_standing(nil, _idle_dates, _threshold_seconds), do: :breaks

  defp grow_standing(rollup, idle_dates, threshold_seconds) do
    cond do
      grow_day?(rollup, threshold_seconds) -> :qualifies
      MapSet.member?(idle_dates, rollup.date) -> :passed_over
      idle_within_shed_age?(rollup, idle_dates) -> :passed_over
      true -> :breaks
    end
  end

  # The whole days the median shed content outlived, and always the day
  # before, which it outlived at least in part.
  defp idle_within_shed_age?(%{median_shed_age_seconds: nil}, _idle_dates), do: false

  defp idle_within_shed_age?(rollup, idle_dates) do
    days = max(div(rollup.median_shed_age_seconds, @seconds_per_day), 1)
    Enum.any?(1..days, &MapSet.member?(idle_dates, Date.add(rollup.date, -&1)))
  end

  # Idle is read from the account's own telemetry, never a calendar: weekends
  # and holidays differ by country, one account can build from several, and a
  # local weekend straddles UTC dates. A day the account wrote nothing to a
  # full ring is idle. A day it barely wrote to one is idle only next to such
  # a day, which is the UTC day a local weekend's edge falls into: a ring that
  # already holds the retention floor sheds about one ring per floor on an
  # ordinary day, so without that anchor every day of a right-sized ring would
  # read as idle instead of saying the claim fits. A ring under the shrink
  # line that evicted nothing is the claim fitting.
  defp idle_dates(by_date, policy) do
    blank_dates = for {date, rollup} <- by_date, blank_day?(rollup, policy), into: MapSet.new(), do: date

    for {date, rollup} <- by_date,
        quiet_day?(rollup, policy),
        next_to_blank_day?(date, blank_dates),
        into: blank_dates,
        do: date
  end

  defp blank_day?(rollup, policy), do: full_ring?(rollup, policy) and rollup.eviction_count == 0

  defp quiet_day?(rollup, policy) do
    full_ring?(rollup, policy) and negligible_evictions?(rollup, policy)
  end

  defp full_ring?(rollup, policy) do
    rollup.snapshot_count > 0 and rollup.max_occupancy_percent != nil and
      rollup.max_occupancy_percent >= policy.shrink_occupancy_percent
  end

  defp next_to_blank_day?(date, blank_dates) do
    MapSet.member?(blank_dates, Date.add(date, -1)) or MapSet.member?(blank_dates, Date.add(date, 1))
  end

  defp negligible_evictions?(%{last_ring_budget_bytes: budget_bytes} = rollup, policy)
       when is_integer(budget_bytes) and budget_bytes > 0,
       do: rollup.evicted_bytes * policy.retention_floor_days <= budget_bytes

  defp negligible_evictions?(_rollup, _policy), do: false

  # As many as the longest window is long: the longest any reading is asked to
  # hold. Past that, the days either side of the gap are no longer one reading.
  defp passable_days(policy) do
    policy.grow_windows
    |> Enum.map(& &1.window_days)
    |> Enum.max()
  end

  # Walks back from today. Today's row is live, so it counts when it qualifies
  # and is passed over when it has not measured enough to: the hour the sweep
  # runs never breaks a streak. One that already contradicts the verdict ends
  # it. Every earlier day passed over spends one of `passable_days`.
  defp qualifying_window(by_date, today, window_days, passable_days, standing) do
    rollup = Map.get(by_date, today)
    yesterday = Date.add(today, -1)

    case standing.(rollup) do
      :qualifies -> collect_window(by_date, yesterday, window_days - 1, passable_days, standing, [rollup])
      :contradicts -> nil
      _standing -> collect_window(by_date, yesterday, window_days, passable_days, standing, [])
    end
  end

  defp collect_window(_by_date, _day, 0, _passable_days, _standing, window), do: window

  defp collect_window(by_date, day, remaining_days, passable_days, standing, window) do
    rollup = Map.get(by_date, day)
    previous_day = Date.add(day, -1)

    case standing.(rollup) do
      :qualifies ->
        collect_window(by_date, previous_day, remaining_days - 1, passable_days, standing, [rollup | window])

      :passed_over when passable_days > 0 ->
        collect_window(by_date, previous_day, remaining_days, passable_days - 1, standing, window)

      _standing ->
        nil
    end
  end

  defp grow_target_bytes(window, claim_bytes, floor_seconds, rung, policy) do
    span_seconds = window |> Enum.map(& &1.median_ring_span_seconds) |> median()

    claim_bytes
    |> projected_bytes(floor_seconds, span_seconds, policy)
    |> min(claim_bytes * max_step_factor(rung, policy))
    |> max(claim_bytes)
    |> round()
  end

  # Projected from the retention the measured claim buys, plus headroom so a
  # correct resize does not land on the boundary it is escaping. A shrink lands
  # on the same point from the other side.
  defp projected_bytes(claim_bytes, floor_seconds, span_seconds, policy) do
    claim_bytes * (floor_seconds / max(span_seconds, 1)) * policy.grow_headroom_factor
  end

  # The bound scales with the confirmation behind the reading: one day buys a
  # doubling, a tier proven across days buys the projection's own answer. It
  # binds only under 45 hours of retention at 2x and 22.5 hours at 4x, so an
  # account near the floor is sized by the projection either way and the one
  # furthest under it arrives in a single rebuild rather than three.
  defp max_step_factor(%{window_days: 1}, policy), do: policy.max_step_factor
  defp max_step_factor(_rung, policy), do: policy.max_confirmed_step_factor

  defp shrink_target_bytes(window, policy) do
    peak_bytes =
      window
      |> Enum.map(&(&1.max_live_segment_bytes || 0))
      |> Enum.max()

    round(peak_bytes * 100 / policy.shrink_target_occupancy_percent)
  end

  defp merge_verdicts(verdicts, current_bytes, context, policy) do
    grows = for {:grow, region, target, claim, evidence} <- verdicts, do: {region, target, claim, evidence}

    shrinks =
      for {:shrink, signal, region, target, claim, evidence} <- verdicts, do: {signal, region, target, claim, evidence}

    cond do
      grows != [] -> finalize_grow(grows, current_bytes, context, policy)
      shrinks != [] and length(shrinks) == length(verdicts) -> finalize_shrink(shrinks, current_bytes, context, policy)
      true -> :none
    end
  end

  defp finalize_grow(grows, current_bytes, context, policy) do
    {region, target_bytes, _claim_bytes, evidence} = Enum.max_by(grows, &elem(&1, 1))
    bytes = target_bytes |> min(quantity_bytes(ceiling(context.plan, policy))) |> max(current_bytes)

    cond do
      bytes > current_bytes -> {:grow, to_gibibyte_quantity(bytes), Map.put(evidence, "region", region)}
      raised = raise_to_account_claim(grows, current_bytes, context, policy) -> raised
      true -> :none
    end
  end

  # A region pinned under the account's claim that runs short is raised to
  # that claim even when its own ring asks for less: the account's content is
  # replicated into every region, so a smaller ring sheds it sooner than the
  # rest. Never past the plan's ceiling, which a claim pinned above it
  # already is.
  defp raise_to_account_claim(grows, current_bytes, context, policy) do
    short = Enum.filter(grows, fn {_region, _target, claim_bytes, _evidence} -> claim_bytes < current_bytes end)

    if short != [] and current_bytes <= quantity_bytes(ceiling(context.plan, policy)) do
      {region, _target_bytes, _claim_bytes, evidence} = Enum.max_by(short, &elem(&1, 1))
      {:grow, context.current_claim_size, Map.put(evidence, "region", region)}
    end
  end

  # One step at most halves the claim, unless a region already runs the
  # account's rotating content on a smaller claim and keeps three floors
  # there: that claim is measured rather than projected, so the step may go to
  # it. A ring that never filled measures nothing about rotating content and
  # does not count. Retention never goes under the claim the plan starts an
  # account at; a ring that never filled may go to the smallest any instance
  # is built with.
  defp finalize_shrink(shrinks, current_bytes, context, policy) do
    {_signal, region, target_bytes, _claim_bytes, evidence} = Enum.max_by(shrinks, &elem(&1, 2))

    measured =
      for {signal, _region, _target_bytes, claim_bytes, _evidence} <- shrinks,
          signal in [:retention, :retention_correction],
          do: claim_bytes

    correction? = Enum.any?(shrinks, &(elem(&1, 0) == :retention_correction))

    step_bytes =
      if correction? do
        ceil(current_bytes * (100 - policy.retention_correction_max_reduction_percent) / 100)
      else
        Enum.min([round(current_bytes / policy.max_step_factor) | measured])
      end

    bytes =
      target_bytes
      |> max(step_bytes)
      |> max(quantity_bytes(shrink_minimum(measured, context.plan)))
      |> min(current_bytes)

    recommended = to_gibibyte_quantity(bytes)

    saving = current_bytes - quantity_bytes(recommended)
    significant? = not correction? or saving * 100 >= current_bytes * policy.retention_correction_min_reduction_percent
    measured_regions = Enum.map(shrinks, &elem(&1, 1))
    missing_regions = Map.keys(Map.get(context, :region_claim_sizes, %{})) -- measured_regions

    if saving > 0 and significant? and (not correction? or missing_regions == []) do
      evidence = Map.put(evidence, "region", region)

      evidence =
        if correction?,
          do: Map.put(evidence, "max_reduction_percent", policy.retention_correction_max_reduction_percent),
          else: evidence

      {:shrink, recommended, evidence}
    else
      :none
    end
  end

  defp shrink_minimum([], _plan), do: Regions.minimum_storage_claim()
  defp shrink_minimum(_measured, plan), do: Regions.storage_profile(plan).claim_size

  defp grow_evidence(window, floor_seconds, threshold_seconds) do
    %{
      "signal" => "shed_age_below_retention_floor",
      "window_days" => length(window),
      "retention_floor_seconds" => floor_seconds,
      "qualifying_threshold_seconds" => threshold_seconds,
      "median_shed_age_seconds" => window |> Enum.map(& &1.median_shed_age_seconds) |> median(),
      "median_ring_span_seconds" => window |> Enum.map(& &1.median_ring_span_seconds) |> median(),
      "evicted_bytes" => window |> Enum.map(& &1.evicted_bytes) |> Enum.sum(),
      "ring_budget_bytes" => ring_budget_bytes(window),
      "ring_turnover" => window |> ring_turnover() |> round_turnover()
    }
  end

  defp round_turnover(nil), do: nil
  defp round_turnover(turnover), do: Float.round(turnover, 1)

  defp shrink_evidence(window, policy) do
    %{
      "signal" => "occupancy_below_threshold",
      "window_days" => length(window),
      "occupancy_threshold_percent" => policy.shrink_occupancy_percent,
      "max_occupancy_percent" => window |> Enum.map(& &1.max_occupancy_percent) |> Enum.max(),
      "peak_live_segment_bytes" => window |> Enum.map(&(&1.max_live_segment_bytes || 0)) |> Enum.max()
    }
  end

  defp retention_evidence(window, floor_seconds, threshold_seconds) do
    %{
      "signal" => "retention_above_floor",
      "window_days" => length(window),
      "retention_floor_seconds" => floor_seconds,
      "qualifying_threshold_seconds" => threshold_seconds,
      "shortest_shed_age_seconds" => shortest(window, :median_shed_age_seconds),
      "shortest_ring_span_seconds" => shortest(window, :median_ring_span_seconds),
      "evicted_bytes" => window |> Enum.map(& &1.evicted_bytes) |> Enum.sum()
    }
  end

  defp shortest(window, key) do
    window
    |> Enum.map(&Map.fetch!(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  # How far a claim may grow. The plan's starting claim, which bounds a
  # retention shrink, is the other place a plan changes the outcome.
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
