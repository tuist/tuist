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
        current_claim_size: "16Gi",
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

      assert {:grow, "20Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 14
      assert evidence["median_shed_age_seconds"] == 233_280
      assert evidence["retention_floor_seconds"] == 3 * @day_seconds
      assert evidence["qualifying_threshold_seconds"] == 3 * @day_seconds
    end

    test "the streak may end yesterday, so a quiet partial day does not break it" do
      rollups =
        marginal_churn(14, Date.add(@today, -1)) ++ [rollup(@today, snapshot_count: 4, max_occupancy_percent: 95)]

      assert {:grow, "20Gi", _evidence} = ClaimSizing.evaluate(context(rollups: rollups))
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

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 2
      assert evidence["qualifying_threshold_seconds"] == 28_800
    end

    test "catastrophic shedding needs only one ring lost to confirm" do
      # Under an hour of retention already rules out ordinary operation, so
      # the volume half of the evidence relaxes: one full ring is enough
      # where eight-hour shedding would have to prove two. Because a ring
      # turns over about once per span it holds, that is also roughly an
      # hour of real time rather than two.
      rollups = 1 |> churn_at(@today, 20 * 60, 30 * 60) |> Enum.map(&Map.put(&1, :evicted_bytes, 18 * @gibibyte))

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 1
      assert evidence["ring_turnover"] == 1.1
      assert evidence["qualifying_threshold_seconds"] == 3_600
    end

    test "catastrophic shedding still needs a whole ring lost" do
      # Half a ring under an hour old is a burst, not a verdict.
      rollups = 1 |> churn_at(@today, 20 * 60, 30 * 60) |> Enum.map(&Map.put(&1, :evicted_bytes, 8 * @gibibyte))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "an hour-old ring does not get the relaxed volume once it is merely severe" do
      # Ninety minutes clears the catastrophic rung, so the account falls to
      # the eight-hour rung and owes the full two rings again.
      rollups = 1 |> churn_at(@today, 90 * 60, 2 * 3_600) |> Enum.map(&Map.put(&1, :evicted_bytes, 18 * @gibibyte))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a single severe day acts when the account cycled its whole ring twice over" do
      # Volume replaces elapsed time on the shortest rung: 40Gi evicted
      # against a 16Gi claim is two and a half rings lost in a day, while the
      # content going out is younger than a working day.
      rollups = 1 |> severe_churn(@today) |> Enum.map(&Map.put(&1, :evicted_bytes, 40 * @gibibyte))

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 1
      assert evidence["ring_turnover"] == 2.5
    end

    test "a single severe day without the volume waits for a second day" do
      # One day of thin evidence can be an afternoon's import burst, so the
      # single-day rung declines it and the two-day rung has nothing yet.
      assert ClaimSizing.evaluate(context(rollups: severe_churn(1, @today))) == :none
    end

    test "every plan confirms on the same evidence and differs only in where it lands" do
      # Same churn, same rung, same window on every plan. Air and Pro land
      # apart here only because they start apart and each step is clamped,
      # not because Air is allowed less in the end.
      rollups = churn_at(2, @today, 7 * 3_600, 12 * 3_600)

      for {plan, current, expected} <- [{:air, "8Gi", "16Gi"}, {:pro, "16Gi", "32Gi"}, {:enterprise, "32Gi", "64Gi"}] do
        context = context(plan: plan, current_claim_size: current, rollups: rollups)

        assert {:grow, ^expected, evidence} = ClaimSizing.evaluate(context)
        assert evidence["window_days"] == 2
        assert evidence["qualifying_threshold_seconds"] == 28_800
      end
    end

    test "enterprise may grow past where the other plans stop" do
      # The shared promise, funded further: at 50Gi pro is done and
      # enterprise keeps stepping, one clamped step at a time, to its own
      # ceiling. This is also what stops enterprise being a plan that can
      # only ever shrink from its starting constant.
      rollups = severe_churn(2, @today)

      assert ClaimSizing.evaluate(context(plan: :pro, current_claim_size: "64Gi", rollups: rollups)) == :none

      assert {:grow, "128Gi", _evidence} =
               ClaimSizing.evaluate(context(plan: :enterprise, current_claim_size: "64Gi", rollups: rollups))

      assert {:grow, "256Gi", _evidence} =
               ClaimSizing.evaluate(context(plan: :enterprise, current_claim_size: "128Gi", rollups: rollups))

      assert ClaimSizing.evaluate(context(plan: :enterprise, current_claim_size: "256Gi", rollups: rollups)) == :none
    end

    test "shedding exactly at a working day falls back to the fractional ladder" do
      # The absolute arm is a strict inequality, so 8 hours does not clear it
      # and the reading lands on the fractional ladder instead, where it is
      # under a third of the floor: five days rather than two.
      rollups = churn_at(2, @today, 8 * 3_600, 12 * 3_600)
      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert ClaimSizing.evaluate(context) == :none

      longer = churn_at(5, @today, 8 * 3_600, 12 * 3_600)

      assert {:grow, "16Gi", evidence} = ClaimSizing.evaluate(context(context, rollups: longer))
      assert evidence["window_days"] == 5
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)
    end

    test "moderate shedding waits out the middle tier" do
      # A sixth of the floor: past the severe tier's threshold, so two days
      # cannot carry it, but it does not serve the full fortnight either.
      assert ClaimSizing.evaluate(context(rollups: moderate_churn(4, @today))) == :none

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(rollups: moderate_churn(5, @today)))
      assert evidence["window_days"] == 5
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)
    end

    test "a marginal reading cannot borrow a shorter tier" do
      # Two and five days of shedding just under the floor stay unproven:
      # only severity buys a shorter window.
      assert ClaimSizing.evaluate(context(rollups: marginal_churn(2, @today))) == :none
      assert ClaimSizing.evaluate(context(rollups: marginal_churn(5, @today))) == :none
    end

    test "air climbs to the shared ceiling one clamped step at a time" do
      # A 12-hour ring against the 3-day floor projects far past the step
      # bound, so each pass doubles rather than jumping. Air is not capped
      # short of Pro any more; it just starts lower, so it takes more
      # separately confirmed steps to arrive.
      rollups =
        churn_days(14, @today,
          median_shed_age_seconds: 1_800,
          median_ring_span_seconds: div(@day_seconds, 2)
        )

      for {current, expected} <- [{"8Gi", "16Gi"}, {"16Gi", "32Gi"}, {"32Gi", "64Gi"}] do
        context = context(plan: :air, current_claim_size: current, rollups: rollups)

        assert {:grow, ^expected, _evidence} = ClaimSizing.evaluate(context)
      end

      assert ClaimSizing.evaluate(context(plan: :air, current_claim_size: "64Gi", rollups: rollups)) == :none
    end

    test "an account already at its plan ceiling gets no proposal" do
      context = context(plan: :pro, current_claim_size: "64Gi", rollups: severe_churn(14, @today))

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

      assert {:grow, "20Gi", _evidence} = ClaimSizing.evaluate(context)
    end

    test "a still-churning ring grows again two days after a resize" do
      # The severity ladder paces consecutive steps too: an account whose
      # claim is still far too small after a resize corrects in days.
      context =
        context(
          rollups: severe_churn(2, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -2), ~T[12:00:00], "Etc/UTC")
        )

      assert {:grow, "32Gi", _evidence} = ClaimSizing.evaluate(context)
    end
  end

  describe "evaluate/2 shrinking" do
    test "proposes shrinking after a long window of low occupancy" do
      # 6Gi peak at the 60% occupancy target asks for 10Gi.
      context = context(current_claim_size: "16Gi", rollups: idle_days(30, @today))

      assert {:shrink, "10Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 30
      assert evidence["max_occupancy_percent"] == 25
    end

    test "one step never less than halves the claim" do
      rollups = idle_days(30, @today, max_live_segment_bytes: 2 * @gibibyte)

      assert {:shrink, "8Gi", _evidence} = ClaimSizing.evaluate(context(rollups: rollups))
    end

    test "never shrinks under the validated minimum claim" do
      rollups =
        idle_days(30, @today,
          max_live_segment_bytes: div(@gibibyte, 2),
          last_ring_budget_bytes: 6 * @gibibyte
        )

      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert ClaimSizing.evaluate(context) == :none
    end

    test "a day without snapshots breaks the idle streak" do
      rollups =
        30
        |> idle_days(@today)
        |> List.replace_at(15, rollup(Date.add(@today, -14), eviction_count: 0))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "an eviction inside the window breaks the idle streak" do
      rollups =
        30
        |> idle_days(@today)
        |> List.replace_at(
          15,
          rollup(Date.add(@today, -14), snapshot_count: 96, max_occupancy_percent: 25, eviction_count: 1)
        )

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a window shorter than the shrink window withholds the proposal" do
      assert ClaimSizing.evaluate(context(rollups: idle_days(29, @today))) == :none
    end

    test "a shrink needs its whole window after the last resize" do
      rollups = idle_days(30, @today)

      recent = context(rollups: rollups, last_resized_at: DateTime.new!(Date.add(@today, -10), ~T[12:00:00], "Etc/UTC"))
      assert ClaimSizing.evaluate(recent) == :none

      settled = context(rollups: rollups, last_resized_at: DateTime.new!(Date.add(@today, -31), ~T[12:00:00], "Etc/UTC"))
      assert {:shrink, "10Gi", _evidence} = ClaimSizing.evaluate(settled)
    end
  end

  describe "evaluate/2 across regions" do
    test "a growing region wins over a shrinking one" do
      rollups =
        moderate_churn(14, @today) ++ Enum.map(idle_days(30, @today), &Map.put(&1, :region, "eu-central"))

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["region"] == "us-east"
    end

    test "shrinking needs every region with data to agree" do
      rollups =
        idle_days(30, @today) ++
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
