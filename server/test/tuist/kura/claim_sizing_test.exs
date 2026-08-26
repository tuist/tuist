defmodule Tuist.Kura.ClaimSizingTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.ClaimSizing

  @gibibyte 1024 * 1024 * 1024
  @today ~D[2026-08-25]
  @day_seconds 86_400

  defp rollup(date, attrs) do
    Map.merge(
      %{
        region: "us-east",
        date: date,
        eviction_count: 0,
        evicted_bytes: 0,
        evicted_artifact_count: 0,
        min_shed_age_seconds: nil,
        median_shed_age_seconds: nil,
        median_ring_span_seconds: nil,
        snapshot_count: 0,
        max_occupancy_percent: nil,
        max_live_segment_bytes: nil,
        last_ring_budget_bytes: nil
      },
      Map.new(attrs)
    )
  end

  defp churn_days(count, end_day, attrs \\ []) do
    for offset <- (count - 1)..0//-1 do
      rollup(
        Date.add(end_day, -offset),
        Keyword.merge(
          [
            eviction_count: 40,
            evicted_bytes: 10 * @gibibyte,
            median_shed_age_seconds: 12 * 3_600,
            median_ring_span_seconds: div(3 * @day_seconds, 2)
          ],
          attrs
        )
      )
    end
  end

  # Churn at a given fraction of the plan's retention floor, which is what
  # picks the confirmation tier. The span stays coherent with the shed age:
  # content cannot be shed younger than the segment holding it is old.
  defp churn_at(count, end_day, shed_seconds, span_seconds) do
    churn_days(count, end_day,
      median_shed_age_seconds: shed_seconds,
      median_ring_span_seconds: span_seconds
    )
  end

  # Pro floor is 3 days. 2.7 days of shedding is just under it: a marginal
  # reading that only the longest tier accepts.
  defp marginal_churn(count, end_day), do: churn_at(count, end_day, 233_280, 3 * @day_seconds)

  # 12 hours against a 3-day floor: a sixth of the floor, the middle tier.
  defp moderate_churn(count, end_day), do: churn_at(count, end_day, 43_200, div(3 * @day_seconds, 2))

  # 30 minutes against a 3-day floor: the ring is churning artifacts it just
  # stored, which is the tier that must not wait.
  defp severe_churn(count, end_day), do: churn_at(count, end_day, 1_800, 3_600)

  defp idle_days(count, end_day, attrs \\ []) do
    for offset <- (count - 1)..0//-1 do
      rollup(
        Date.add(end_day, -offset),
        Keyword.merge(
          [
            snapshot_count: 96,
            max_occupancy_percent: 25,
            max_live_segment_bytes: 6 * @gibibyte,
            last_ring_budget_bytes: 25 * @gibibyte
          ],
          attrs
        )
      )
    end
  end

  defp context(attrs) do
    context(
      %{
        plan: :pro,
        current_claim_size: "30Gi",
        rollups: [],
        last_resized_at: nil,
        today: @today
      },
      attrs
    )
  end

  defp context(base, attrs), do: Map.merge(base, Map.new(attrs))

  describe "evaluate/2 growth" do
    test "proposes growth after a sustained streak of churn under the retention floor" do
      # Pro floor is 3 days and the shedding sits just under it, so only the
      # longest tier accepts it. The ring holds 3 days, so the projection is
      # the floor plus headroom.
      context = context(rollups: marginal_churn(14, @today))

      assert {:grow, "38Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 14
      assert evidence["median_shed_age_seconds"] == 233_280
      assert evidence["retention_floor_seconds"] == 3 * @day_seconds
      assert evidence["qualifying_threshold_seconds"] == 3 * @day_seconds
    end

    test "the streak may end yesterday, so a quiet partial day does not break it" do
      rollups =
        marginal_churn(14, Date.add(@today, -1)) ++ [rollup(@today, snapshot_count: 4, max_occupancy_percent: 95)]

      assert {:grow, "38Gi", _evidence} = ClaimSizing.evaluate(context(rollups: rollups))
    end

    test "one day without evictions inside the window withholds the proposal" do
      rollups =
        14
        |> marginal_churn(@today)
        |> List.replace_at(7, rollup(Date.add(@today, -6), snapshot_count: 96, max_occupancy_percent: 95))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a marginal streak shorter than the longest window withholds the proposal" do
      assert ClaimSizing.evaluate(context(rollups: marginal_churn(13, @today))) == :none
    end

    test "shed age at or above the floor is not churn" do
      rollups = churn_days(14, @today, median_shed_age_seconds: 4 * @day_seconds)

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "severe shedding acts on two days instead of serving out the long window" do
      # 30 minutes against a 3-day floor: the ring is churning artifacts it
      # just stored, and every further day of confirmation is a day the
      # account rebuilds what it already built. Turnover here is 1.25 rings a
      # day, short of the single-day rung.
      context = context(rollups: severe_churn(2, @today))

      assert {:grow, "50Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 2
      assert evidence["qualifying_threshold_seconds"] == 28_800
    end

    test "a single severe day acts when the account cycled its whole ring twice over" do
      # Volume replaces elapsed time on the shortest rung: 75Gi evicted
      # against a 30Gi claim is two and a half rings lost in a day, while the
      # content going out is younger than a working day.
      rollups = 1 |> severe_churn(@today) |> Enum.map(&Map.put(&1, :evicted_bytes, 75 * @gibibyte))

      assert {:grow, "50Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 1
      assert evidence["ring_turnover"] == 2.5
    end

    test "a single severe day without the volume waits for a second day" do
      # One day of thin evidence can be an afternoon's import burst, so the
      # single-day rung declines it and the two-day rung has nothing yet.
      assert ClaimSizing.evaluate(context(rollups: severe_churn(1, @today))) == :none
    end

    test "air acts on the absolute arm its own floor would have slowed" do
      # Seven hours is 29% of Air's one-day floor, so the fractional ladder
      # would have made the plan least able to absorb churn wait five days.
      rollups = churn_at(2, @today, 7 * 3_600, 12 * 3_600)
      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert {:grow, "16Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 2
      assert evidence["qualifying_threshold_seconds"] == 28_800
    end

    test "shedding exactly at a working day falls back to the fractional ladder" do
      # The absolute arm is a strict inequality, so 8 hours does not clear it
      # and Air lands on the fractional ladder instead, where it is a third
      # of the floor: five days rather than two.
      rollups = churn_at(2, @today, 8 * 3_600, 12 * 3_600)
      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert ClaimSizing.evaluate(context) == :none

      longer = churn_at(5, @today, 8 * 3_600, 12 * 3_600)

      assert {:grow, "16Gi", evidence} = ClaimSizing.evaluate(context(context, rollups: longer))
      assert evidence["window_days"] == 5
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * @day_seconds)
    end

    test "moderate shedding waits out the middle tier" do
      # A sixth of the floor: past the severe tier's threshold, so two days
      # cannot carry it, but it does not serve the full fortnight either.
      assert ClaimSizing.evaluate(context(rollups: moderate_churn(4, @today))) == :none

      assert {:grow, "50Gi", evidence} = ClaimSizing.evaluate(context(rollups: moderate_churn(5, @today)))
      assert evidence["window_days"] == 5
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)
    end

    test "a marginal reading cannot borrow a shorter tier" do
      # Two and five days of shedding just under the floor stay unproven:
      # only severity buys a shorter window.
      assert ClaimSizing.evaluate(context(rollups: marginal_churn(2, @today))) == :none
      assert ClaimSizing.evaluate(context(rollups: marginal_churn(5, @today))) == :none
    end

    test "air grows within its narrow band" do
      # Air floor is 1 day against a 12-hour ring: projection is 2x with
      # headroom, clamped to the step bound and Air's ceiling, both 16Gi.
      rollups =
        churn_days(14, @today,
          median_shed_age_seconds: 1_800,
          median_ring_span_seconds: div(@day_seconds, 2)
        )

      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert {:grow, "16Gi", _evidence} = ClaimSizing.evaluate(context)
    end

    test "an account already at its plan ceiling gets no proposal" do
      context = context(plan: :enterprise, current_claim_size: "50Gi", rollups: severe_churn(14, @today))

      assert ClaimSizing.evaluate(context) == :none
    end

    test "days at or before the last resize cannot qualify a window" do
      # The resize sits mid-window: the churn before it measured the old
      # ring, so only 9 post-resize days remain and the marginal streak is
      # short of its tier.
      context =
        context(
          rollups: marginal_churn(14, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -10), ~T[12:00:00], "Etc/UTC")
        )

      assert ClaimSizing.evaluate(context) == :none
    end

    test "a still-undersized ring grows again once a full window postdates the resize" do
      # 14 marginal churning days strictly after the resize day: the evidence
      # window itself is the pacing, not a flat cooldown.
      context =
        context(
          rollups: marginal_churn(14, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -14), ~T[12:00:00], "Etc/UTC")
        )

      assert {:grow, "38Gi", _evidence} = ClaimSizing.evaluate(context)
    end

    test "a still-churning ring grows again two days after a resize" do
      # The severity ladder paces consecutive steps too: an account whose
      # claim is still far too small after a resize corrects in days.
      context =
        context(
          rollups: severe_churn(2, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -2), ~T[12:00:00], "Etc/UTC")
        )

      assert {:grow, "50Gi", _evidence} = ClaimSizing.evaluate(context)
    end
  end

  describe "evaluate/2 shrinking" do
    test "proposes shrinking after a long window of low occupancy" do
      # 6Gi peak at the 60% occupancy target asks for 10Gi.
      context = context(current_claim_size: "16Gi", rollups: idle_days(90, @today))

      assert {:shrink, "10Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 90
      assert evidence["max_occupancy_percent"] == 25
    end

    test "one step never less than halves the claim" do
      rollups = idle_days(90, @today, max_live_segment_bytes: 2 * @gibibyte)

      assert {:shrink, "15Gi", _evidence} = ClaimSizing.evaluate(context(rollups: rollups))
    end

    test "never shrinks under the validated minimum claim" do
      rollups =
        idle_days(90, @today,
          max_live_segment_bytes: div(@gibibyte, 2),
          last_ring_budget_bytes: 6 * @gibibyte
        )

      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert ClaimSizing.evaluate(context) == :none
    end

    test "a day without snapshots breaks the idle streak" do
      rollups =
        90
        |> idle_days(@today)
        |> List.replace_at(45, rollup(Date.add(@today, -44), eviction_count: 0))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "an eviction inside the window breaks the idle streak" do
      rollups =
        90
        |> idle_days(@today)
        |> List.replace_at(
          45,
          rollup(Date.add(@today, -44), snapshot_count: 96, max_occupancy_percent: 25, eviction_count: 1)
        )

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a window shorter than 90 days withholds the proposal" do
      assert ClaimSizing.evaluate(context(rollups: idle_days(89, @today))) == :none
    end

    test "a shrink needs its whole window after the last resize" do
      rollups = idle_days(90, @today)

      recent = context(rollups: rollups, last_resized_at: DateTime.new!(Date.add(@today, -30), ~T[12:00:00], "Etc/UTC"))
      assert ClaimSizing.evaluate(recent) == :none

      settled = context(rollups: rollups, last_resized_at: DateTime.new!(Date.add(@today, -91), ~T[12:00:00], "Etc/UTC"))
      assert {:shrink, "15Gi", _evidence} = ClaimSizing.evaluate(settled)
    end
  end

  describe "evaluate/2 across regions" do
    test "a growing region wins over a shrinking one" do
      rollups =
        moderate_churn(14, @today) ++ Enum.map(idle_days(90, @today), &Map.put(&1, :region, "eu-central"))

      assert {:grow, "50Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["region"] == "us-east"
    end

    test "shrinking needs every region with data to agree" do
      rollups =
        idle_days(90, @today) ++
          Enum.map(churn_days(5, @today, median_shed_age_seconds: 5 * @day_seconds), &Map.put(&1, :region, "eu-central"))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end
  end

  test "an unparsable current claim yields no proposal" do
    assert ClaimSizing.evaluate(context(current_claim_size: "whatever", rollups: churn_days(14, @today))) == :none
  end

  test "no rollups yield no proposal" do
    assert ClaimSizing.evaluate(context([])) == :none
  end
end
