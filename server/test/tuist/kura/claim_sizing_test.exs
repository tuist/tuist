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
        last_ring_budget_bytes: nil,
        min_ring_budget_bytes: nil
      },
      Map.new(attrs)
    )
  end

  # The budget is the ring a 16Gi claim funds once upload staging, a spare
  # segment and the index are reserved, matching the default context's claim.
  defp churn_days(count, end_day, attrs \\ []) do
    for offset <- (count - 1)..0//-1 do
      rollup(
        Date.add(end_day, -offset),
        Keyword.merge(
          [
            eviction_count: 40,
            evicted_bytes: 10 * @gibibyte,
            median_shed_age_seconds: 12 * 3_600,
            median_ring_span_seconds: div(3 * @day_seconds, 2),
            last_ring_budget_bytes: 13 * @gibibyte
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

  defp fitting_days(count, end_day, attrs \\ []) do
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
        capped_resize_from: nil,
        today: @today
      },
      attrs
    )
  end

  defp context(base, attrs), do: Map.merge(base, Map.new(attrs))

  # A full ring the account wrote nothing to.
  defp idle_days(count, end_day) do
    for offset <- (count - 1)..0//-1 do
      rollup(Date.add(end_day, -offset),
        snapshot_count: 96,
        max_occupancy_percent: 98,
        last_ring_budget_bytes: 13 * @gibibyte
      )
    end
  end

  # Five UTC days of an enterprise instance on a 26.5 GiB ring, ending at
  # `end_day`: an ordinary busy day, a day the account barely built, a day it
  # did not build at all, the first busy day after them, and a busy day still
  # in progress. The last four are readings production recorded.
  defp weekend_days(end_day) do
    ring_bytes = round(26.5 * @gibibyte)

    [
      {98, 1.65, 73_800, 82_800, 98},
      {13, 0.23, 128_160, 136_800, 98},
      {0, 0, nil, nil, 98},
      {111, 2.05, 253_440, 259_200, 98},
      {52, 0.95, 75_600, 90_000, 97}
    ]
    |> Enum.with_index(-4)
    |> Enum.map(fn {{evictions, rings, shed_seconds, span_seconds, occupancy}, offset} ->
      rollup(Date.add(end_day, offset),
        eviction_count: evictions,
        evicted_bytes: round(rings * ring_bytes),
        median_shed_age_seconds: shed_seconds,
        median_ring_span_seconds: span_seconds,
        snapshot_count: 96,
        max_occupancy_percent: occupancy,
        last_ring_budget_bytes: ring_bytes
      )
    end)
  end

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

    test "a day without evictions breaks growth on a roomy ring and is passed over on a full one" do
      # Nothing evicted from a ring under the shrink line is the claim fitting:
      # evidence against growing and toward shrinking. Nothing evicted from a
      # full ring is an account that did not build, which is evidence of
      # neither.
      slot = Date.add(@today, -6)
      streak = marginal_churn(15, @today)
      [fitting] = fitting_days(1, slot)
      [idle] = idle_days(1, slot)

      assert {:grow, "20Gi", %{"window_days" => 14}} =
               ClaimSizing.evaluate(context(rollups: List.replace_at(streak, 8, idle)))

      assert ClaimSizing.evaluate(context(rollups: List.replace_at(streak, 8, fitting))) == :none
      assert {:shrink, "10Gi", _evidence} = ClaimSizing.evaluate(context(rollups: fitting_days(30, @today)))
    end

    test "ordinary days of a right-sized ring break the window rather than being passed over" do
      # A ring that already holds the retention floor evicts about one ring per
      # floor every ordinary day, which is the volume an idle day sheds. Those
      # days say the claim fits, so they break the window, and two spikes ten
      # days apart cannot confirm each other.
      healthy =
        11
        |> churn_at(@today, 80 * 3_600, 80 * 3_600)
        |> Enum.map(
          &Map.merge(&1, %{
            evicted_bytes: round(0.3 * 13 * @gibibyte),
            snapshot_count: 96,
            max_occupancy_percent: 98
          })
        )

      spike = fn rollup ->
        Map.merge(rollup, %{
          evicted_bytes: round(1.2 * 13 * @gibibyte),
          median_shed_age_seconds: 6 * 3_600,
          median_ring_span_seconds: 12 * 3_600
        })
      end

      rollups = healthy |> List.update_at(0, spike) |> List.update_at(10, spike)

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none

      # Two spike days in a row confirm each other, as they did before.
      assert {:grow, "64Gi", %{"window_days" => 2}} =
               ClaimSizing.evaluate(context(rollups: List.update_at(rollups, 9, spike)))
    end

    test "a weekend the account did not build through neither confirms nor breaks growth" do
      # The ring holds about 21 hours on a busy day. Saturday cycled under a
      # quarter of a ring, a rate at which the ring would hold four days, so
      # its evictions are the tail of Friday's builds rather than a reading of
      # the claim. Sunday evicted nothing from a full ring. Monday's 70 hours
      # is Friday's builds aged by the weekend. Friday and Tuesday are the
      # readings, and together they cycled more than two rings.
      rollups = weekend_days(~D[2026-09-15])

      context =
        context(plan: :enterprise, current_claim_size: "32Gi", today: ~D[2026-09-15], rollups: rollups)

      assert {:grow, "120Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 2
      assert evidence["median_shed_age_seconds"] == 74_700
      assert evidence["ring_turnover"] == 2.6
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)

      # Monday cannot stand in for Friday: drop Friday and Tuesday has nothing
      # to confirm it.
      assert ClaimSizing.evaluate(context(context, rollups: tl(rollups))) == :none
    end

    test "a Friday and Saturday weekend is passed over the same as a Saturday and Sunday one" do
      # Nothing reads a weekday: the same week a day earlier puts the idle days
      # on Friday and Saturday and the first busy day on Sunday.
      assert Enum.map([~D[2026-09-12], ~D[2026-09-13]], &Date.day_of_week/1) == [6, 7]
      assert Enum.map([~D[2026-09-11], ~D[2026-09-12]], &Date.day_of_week/1) == [5, 6]

      saturday_sunday =
        context(
          plan: :enterprise,
          current_claim_size: "32Gi",
          today: ~D[2026-09-15],
          rollups: weekend_days(~D[2026-09-15])
        )

      friday_saturday = context(saturday_sunday, today: ~D[2026-09-14], rollups: weekend_days(~D[2026-09-14]))

      assert {:grow, "120Gi", _evidence} = ClaimSizing.evaluate(friday_saturday)
      assert ClaimSizing.evaluate(friday_saturday) == ClaimSizing.evaluate(saturday_sunday)
    end

    test "the first busy day after idle days still counts when its reading clears the bar" do
      # An idle gap can only lengthen a shed age, so a day that sheds in half
      # an hour despite the gap is as honest as any other and pairs with the
      # busy day before it.
      rollups =
        severe_churn(1, Date.add(@today, -3)) ++ idle_days(2, Date.add(@today, -1)) ++ severe_churn(1, @today)

      assert {:grow, "64Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 2
      assert evidence["qualifying_threshold_seconds"] == 28_800
    end

    test "a qualifying reading counts however little the day evicted" do
      # Seven-hour shedding on a full ring confirms on two days. Today's row is
      # live and has only evicted a fifth of a ring so far, which is under the
      # idle line, but an idle gap can only lengthen a shed age: a short one on
      # a quiet day is still the ring running short.
      [earlier, later] =
        2
        |> churn_at(@today, 7 * 3_600, 12 * 3_600)
        |> Enum.map(&Map.merge(&1, %{snapshot_count: 96, max_occupancy_percent: 98}))

      ring_bytes = 13 * @gibibyte
      busy = fn rollup -> Map.put(rollup, :evicted_bytes, round(0.8 * ring_bytes)) end
      quiet = fn rollup -> Map.put(rollup, :evicted_bytes, round(0.2 * ring_bytes)) end

      assert {:grow, "64Gi", %{"window_days" => 2}} =
               ClaimSizing.evaluate(context(rollups: [busy.(earlier), quiet.(later)]))

      assert {:grow, "64Gi", %{"window_days" => 2}} =
               ClaimSizing.evaluate(context(rollups: [quiet.(earlier), busy.(later)]))
    end

    test "an account that stops building keeps its streak only as long as the longest window" do
      # Idle days are passed over, but no more of them than the longest window
      # is long, so an account that stopped building does not keep growing
      # off its last busy days.
      busy =
        2
        |> churn_at(Date.add(@today, -15), 20 * 3_600, 30 * 3_600)
        |> Enum.map(&Map.put(&1, :evicted_bytes, 15 * @gibibyte))

      assert {:grow, "48Gi", _evidence} = ClaimSizing.evaluate(context(rollups: busy ++ idle_days(15, @today)))

      earlier = Enum.map(busy, &Map.update!(&1, :date, fn date -> Date.add(date, -1) end))

      assert ClaimSizing.evaluate(context(rollups: earlier ++ idle_days(16, @today))) == :none
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
      # account rebuilds what it already built. Turnover here is 0.8 rings a
      # day, short of the single-day rung.
      context = context(rollups: severe_churn(2, @today))

      assert {:grow, "64Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 2
      assert evidence["qualifying_threshold_seconds"] == 28_800
    end

    test "catastrophic shedding needs only one ring lost to confirm" do
      # Under an hour of retention already rules out ordinary operation, so
      # the volume half of the evidence relaxes: one full ring is enough
      # where eight-hour shedding would have to prove two. Because a ring
      # turns over about once per span it holds, that is also roughly an
      # hour of real time rather than two.
      rollups = 1 |> churn_at(@today, 20 * 60, 30 * 60) |> Enum.map(&Map.put(&1, :evicted_bytes, 14 * @gibibyte))

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 1
      assert evidence["ring_budget_bytes"] == 13 * @gibibyte
      assert evidence["ring_turnover"] == 1.1
      assert evidence["qualifying_threshold_seconds"] == 3_600
    end

    test "catastrophic shedding still needs a whole ring lost" do
      # Half a ring under an hour old is a burst, not a verdict.
      rollups = 1 |> churn_at(@today, 20 * 60, 30 * 60) |> Enum.map(&Map.put(&1, :evicted_bytes, 6 * @gibibyte))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "an hour-old ring does not get the relaxed volume once it is merely severe" do
      # Ninety minutes clears the catastrophic rung, so the account falls to
      # the eight-hour rung and owes the full two rings again.
      rollups = 1 |> churn_at(@today, 90 * 60, 2 * 3_600) |> Enum.map(&Map.put(&1, :evicted_bytes, 14 * @gibibyte))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a single severe day acts when the account cycled its whole ring twice over" do
      # Volume replaces elapsed time on the shortest rung: 33Gi evicted
      # against a 13Gi ring is two and a half rings lost in a day, while the
      # content going out is younger than a working day.
      rollups = 1 |> severe_churn(@today) |> Enum.map(&Map.put(&1, :evicted_bytes, 33 * @gibibyte))

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 1
      assert evidence["ring_turnover"] == 2.5
    end

    test "turnover is measured against the ring the nodes ran, not the claim funding it" do
      # A claim also funds upload staging, a spare segment and the index, so
      # an 8Gi claim runs a 5Gi ring. 11Gi shed in a day is 2.2 rings of what
      # the account actually cycled and only 1.4 of the claim, so measuring
      # the claim would hold the eight-hour rung shut while the ring turned
      # over twice.
      rollups =
        1
        |> churn_at(@today, 6 * 3_600, 12 * 3_600)
        |> Enum.map(&Map.merge(&1, %{evicted_bytes: 11 * @gibibyte, last_ring_budget_bytes: 5 * @gibibyte}))

      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert {:grow, "16Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 1
      assert evidence["ring_budget_bytes"] == 5 * @gibibyte
      assert evidence["ring_turnover"] == 2.2
    end

    test "a window with no measured ring withholds the rungs that gate on turnover" do
      # Nothing reported a ring budget, so there is no honest denominator and
      # the volume rungs stay shut rather than falling back to the claim. The
      # reading waits for the two-day rung, which buys its confirmation with
      # elapsed time instead.
      rollups =
        2
        |> churn_at(@today, 20 * 60, 30 * 60)
        |> Enum.map(&Map.merge(&1, %{evicted_bytes: 40 * @gibibyte, last_ring_budget_bytes: nil}))

      assert ClaimSizing.evaluate(context(rollups: Enum.take(rollups, -1))) == :none

      assert {:grow, "64Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 2
      assert evidence["ring_budget_bytes"] == nil
      assert evidence["ring_turnover"] == nil
    end

    test "a window whose days disagree is measured against the smallest ring it ran" do
      # Days normally agree, because a window never spans a resize. When they
      # do not, every byte in the sum went out against a ring at least this
      # small, so the smaller of the two is the denominator.
      [older, newer] = churn_at(2, @today, 20 * 60, 30 * 60)

      rollups = [
        Map.put(older, :last_ring_budget_bytes, 5 * @gibibyte),
        Map.put(newer, :last_ring_budget_bytes, 13 * @gibibyte)
      ]

      assert {:grow, "64Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 2
      assert evidence["ring_budget_bytes"] == 5 * @gibibyte
      assert evidence["ring_turnover"] == 4.0
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

      for {plan, current, expected} <- [{:air, "8Gi", "32Gi"}, {:pro, "16Gi", "64Gi"}, {:enterprise, "32Gi", "128Gi"}] do
        context = context(plan: plan, current_claim_size: current, rollups: rollups)

        assert {:grow, ^expected, evidence} = ClaimSizing.evaluate(context)
        assert evidence["window_days"] == 2
        assert evidence["qualifying_threshold_seconds"] == 28_800
      end
    end

    test "enterprise may grow past where the other plans stop" do
      # The shared promise, funded further: at 64Gi pro is done and
      # enterprise keeps stepping, in bounded steps, to its own ceiling. This
      # is also what stops enterprise being a plan that can only ever shrink
      # from its starting constant.
      rollups = severe_churn(2, @today)

      assert ClaimSizing.evaluate(context(plan: :pro, current_claim_size: "64Gi", rollups: rollups)) == :none

      assert {:grow, "256Gi", _evidence} =
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

      assert {:grow, "32Gi", evidence} = ClaimSizing.evaluate(context(context, rollups: longer))
      assert evidence["window_days"] == 5
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)
    end

    test "a tier under a third of the floor is bought down to two days by the ring it cycles" do
      # 20 hours of retention clears every absolute arm, so elapsed time on
      # its own owes five days. A ring that cycles once a day is not waiting
      # on further evidence: what it holds is already younger than the day
      # the account will next build against.
      rollups =
        2
        |> churn_at(@today, 20 * 3_600, 30 * 3_600)
        |> Enum.map(&Map.put(&1, :evicted_bytes, 15 * @gibibyte))

      assert {:grow, "48Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["window_days"] == 2
      assert evidence["ring_turnover"] == 2.3
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)
    end

    test "the same tier without a cycled ring serves out its five days" do
      # Three quarters of a ring in a day is an account shedding at the
      # margin rather than one thrashing, so it waits for the longer window
      # like any other reading that cannot pay in volume.
      assert ClaimSizing.evaluate(context(rollups: churn_at(2, @today, 20 * 3_600, 30 * 3_600))) == :none

      assert {:grow, "48Gi", evidence} =
               ClaimSizing.evaluate(context(rollups: churn_at(5, @today, 20 * 3_600, 30 * 3_600)))

      assert evidence["window_days"] == 5
    end

    test "the step a reading may take scales with the confirmation behind it" do
      # The projection here runs far past either bound, so the bound is what
      # lands: a single day's reading doubles, and a tier confirmed across
      # days takes four times. Fewer and better-aimed steps is fewer rebuilds
      # for a badly undersized account, which is the only place it binds.
      one_day = 1 |> severe_churn(@today) |> Enum.map(&Map.put(&1, :evicted_bytes, 33 * @gibibyte))

      assert {:grow, "32Gi", %{"window_days" => 1}} = ClaimSizing.evaluate(context(rollups: one_day))
      assert {:grow, "64Gi", %{"window_days" => 2}} = ClaimSizing.evaluate(context(rollups: severe_churn(2, @today)))
    end

    test "moderate shedding waits out the middle tier" do
      # A sixth of the floor: past the severe tier's threshold, so two days
      # cannot carry it, but it does not serve the full fortnight either.
      assert ClaimSizing.evaluate(context(rollups: moderate_churn(4, @today))) == :none

      assert {:grow, "40Gi", evidence} = ClaimSizing.evaluate(context(rollups: moderate_churn(5, @today)))
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
      # bound, so each pass takes the bound. Air is not capped
      # short of Pro any more; it just starts lower, so it takes more
      # separately confirmed steps to arrive.
      rollups =
        churn_days(14, @today,
          median_shed_age_seconds: 1_800,
          median_ring_span_seconds: div(@day_seconds, 2)
        )

      for {current, expected} <- [{"8Gi", "32Gi"}, {"16Gi", "64Gi"}, {"32Gi", "64Gi"}] do
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

      assert {:grow, "64Gi", _evidence} = ClaimSizing.evaluate(context)
    end
  end

  describe "evaluate/2 after a capped resize" do
    # A 16Gi claim grown to 32Gi runs a 26Gi ring. 21 hours of shedding sits
    # under a third of the 3-day floor, and 20Gi a day is under one ring, so
    # only the five-day rung accepts it on its own and the fast track not at
    # all.
    defp resized_churn(count, end_day, attrs \\ []) do
      churn_days(
        count,
        end_day,
        Keyword.merge(
          [
            median_shed_age_seconds: 21 * 3_600,
            median_ring_span_seconds: 21 * 3_600,
            evicted_bytes: 20 * @gibibyte,
            last_ring_budget_bytes: 26 * @gibibyte,
            min_ring_budget_bytes: 26 * @gibibyte
          ],
          attrs
        )
      )
    end

    defp resized_context(attrs) do
      context(
        Keyword.merge(
          [
            plan: :enterprise,
            current_claim_size: "32Gi",
            last_resized_at: DateTime.new!(Date.add(@today, -1), ~T[14:00:00], "Etc/UTC"),
            capped_resize_from: "16Gi"
          ],
          attrs
        )
      )
    end

    test "grows on one qualifying day of the resized ring that shed a whole ring" do
      assert ClaimSizing.evaluate(resized_context(rollups: resized_churn(1, @today))) == :none

      rollups = resized_churn(1, @today, evicted_bytes: 30 * @gibibyte)

      assert {:grow, "64Gi", evidence} = ClaimSizing.evaluate(resized_context(rollups: rollups))
      assert evidence["window_days"] == 1
      assert evidence["ring_turnover"] == 1.2
      assert evidence["qualifying_threshold_seconds"] == round(0.34 * 3 * @day_seconds)
      assert evidence["after_capped_resize"] == true
    end

    test "a rebuilt ring shedding its first segments does not grow" do
      # A 16Gi claim capped at 64Gi rebuilds a 51 GiB ring that refills and
      # sheds two segments 118,552 seconds after the resize: as old as the
      # ring itself, which is still younger than the retention floor.
      ring_bytes = 51 * @gibibyte

      rollups = [
        rollup(@today,
          eviction_count: 2,
          evicted_bytes: 1_069_409_935,
          median_shed_age_seconds: 118_552,
          median_ring_span_seconds: 118_552,
          last_ring_budget_bytes: ring_bytes,
          min_ring_budget_bytes: ring_bytes
        )
      ]

      context =
        context(
          plan: :enterprise,
          current_claim_size: "64Gi",
          capped_resize_from: "16Gi",
          last_resized_at: DateTime.new!(Date.add(@today, -1), ~T[00:30:00], "Etc/UTC"),
          rollups: rollups
        )

      assert ClaimSizing.evaluate(context) == :none
    end

    test "a rebuilt ring that cycles within hours still grows on its first day" do
      ring_bytes = 51 * @gibibyte

      rollups = [
        rollup(@today,
          eviction_count: 120,
          evicted_bytes: 60 * @gibibyte,
          median_shed_age_seconds: 5 * 3_600,
          median_ring_span_seconds: 6 * 3_600,
          last_ring_budget_bytes: ring_bytes,
          min_ring_budget_bytes: ring_bytes
        )
      ]

      context =
        context(
          plan: :enterprise,
          current_claim_size: "64Gi",
          capped_resize_from: "16Gi",
          last_resized_at: DateTime.new!(Date.add(@today, -1), ~T[00:30:00], "Etc/UTC"),
          rollups: rollups
        )

      assert {:grow, "128Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["window_days"] == 1
      assert evidence["ring_turnover"] == 1.2
      assert evidence["after_capped_resize"] == true
    end

    test "an uncapped previous resize serves out the normal window" do
      context =
        resized_context(
          capped_resize_from: nil,
          last_resized_at: DateTime.new!(Date.add(@today, -5), ~T[14:00:00], "Etc/UTC")
        )

      assert ClaimSizing.evaluate(context(context, rollups: resized_churn(1, @today))) == :none
      assert ClaimSizing.evaluate(context(context, rollups: resized_churn(4, @today))) == :none

      assert {:grow, "128Gi", evidence} = ClaimSizing.evaluate(context(context, rollups: resized_churn(5, @today)))
      assert evidence["window_days"] == 5
      refute Map.has_key?(evidence, "after_capped_resize")
    end

    test "a day no longer shedding under the floor does not grow" do
      rollups =
        resized_churn(1, @today, median_shed_age_seconds: 4 * @day_seconds, median_ring_span_seconds: 4 * @day_seconds)

      assert ClaimSizing.evaluate(resized_context(rollups: rollups)) == :none
    end

    test "a day without evictions does not qualify" do
      rollups = [
        rollup(@today,
          snapshot_count: 96,
          max_occupancy_percent: 70,
          max_live_segment_bytes: 18 * @gibibyte,
          last_ring_budget_bytes: 26 * @gibibyte,
          min_ring_budget_bytes: 26 * @gibibyte
        )
      ]

      assert ClaimSizing.evaluate(resized_context(rollups: rollups)) == :none
    end

    test "idle days after a qualifying day of the resized ring do not end the fast track" do
      # Days the account did not build are passed over here as in any window,
      # so the resized ring's one qualifying day still confirms two days later.
      idle =
        for offset <- [-1, 0] do
          rollup(Date.add(@today, offset),
            snapshot_count: 96,
            max_occupancy_percent: 98,
            last_ring_budget_bytes: 26 * @gibibyte,
            min_ring_budget_bytes: 26 * @gibibyte
          )
        end

      context = resized_context(last_resized_at: DateTime.new!(Date.add(@today, -3), ~T[14:00:00], "Etc/UTC"))
      rollups = resized_churn(1, Date.add(@today, -2), evicted_bytes: 30 * @gibibyte) ++ idle

      assert {:grow, "64Gi", %{"window_days" => 1, "after_capped_resize" => true}} =
               ClaimSizing.evaluate(context(context, rollups: rollups))
    end

    test "a day still reporting the ring the capped resize replaced does not qualify" do
      for ring_budget_bytes <- [13 * @gibibyte, nil] do
        rollups =
          resized_churn(1, @today, last_ring_budget_bytes: ring_budget_bytes, min_ring_budget_bytes: ring_budget_bytes)

        assert ClaimSizing.evaluate(resized_context(rollups: rollups)) == :none
      end
    end

    test "a day that also ran the replaced ring does not qualify, whichever ring reported last" do
      # Evictions cover the whole day, so a rollout finishing after midnight
      # sheds on the old ring before the resized one snapshots.
      rollups = resized_churn(1, @today, min_ring_budget_bytes: 13 * @gibibyte)

      assert ClaimSizing.evaluate(resized_context(rollups: rollups)) == :none
    end

    test "the resize day itself does not qualify" do
      context = resized_context(last_resized_at: DateTime.new!(@today, ~T[09:00:00], "Etc/UTC"))

      assert ClaimSizing.evaluate(context(context, rollups: resized_churn(1, @today))) == :none
    end

    test "a rung fast-tracks only until its own window could have run since the resize" do
      # 60 hours clears every rung but the fourteen-day one.
      rollups =
        resized_churn(1, @today,
          median_shed_age_seconds: 60 * 3_600,
          median_ring_span_seconds: 60 * 3_600,
          evicted_bytes: 30 * @gibibyte
        )

      within = resized_context(last_resized_at: DateTime.new!(Date.add(@today, -14), ~T[14:00:00], "Etc/UTC"))

      assert {:grow, "48Gi", %{"after_capped_resize" => true}} =
               ClaimSizing.evaluate(context(within, rollups: rollups))

      expired = resized_context(last_resized_at: DateTime.new!(Date.add(@today, -15), ~T[14:00:00], "Etc/UTC"))

      assert ClaimSizing.evaluate(context(expired, rollups: rollups)) == :none
    end

    test "the fast-tracked step keeps the one-day bound and the plan ceiling" do
      # The projection is far past 4x, so only the bound decides where it lands.
      rollups =
        resized_churn(1, @today,
          median_shed_age_seconds: 2 * 3_600,
          median_ring_span_seconds: 3 * 3_600,
          evicted_bytes: 30 * @gibibyte
        )

      assert {:grow, "64Gi", %{"window_days" => 1, "after_capped_resize" => true}} =
               ClaimSizing.evaluate(resized_context(plan: :enterprise, rollups: rollups))

      assert {:grow, "256Gi", %{"window_days" => 1, "after_capped_resize" => true}} =
               ClaimSizing.evaluate(
                 resized_context(
                   plan: :enterprise,
                   current_claim_size: "200Gi",
                   capped_resize_from: "100Gi",
                   rollups:
                     Enum.map(
                       rollups,
                       &Map.merge(&1, %{
                         evicted_bytes: 200 * @gibibyte,
                         last_ring_budget_bytes: 190 * @gibibyte,
                         min_ring_budget_bytes: 190 * @gibibyte
                       })
                     )
                 )
               )
    end
  end

  describe "capped_growth?/2" do
    test "a growth clamped below the projection its evidence names was capped" do
      # 20,528 seconds of ring span against a 3-day floor projects about 15.8x.
      proposal = %{
        direction: :grow,
        current_claim_size: "16Gi",
        recommended_claim_size: "32Gi",
        evidence: %{"retention_floor_seconds" => 3 * @day_seconds, "median_ring_span_seconds" => 20_528}
      }

      assert ClaimSizing.capped_growth?(proposal)
      refute ClaimSizing.capped_growth?(%{proposal | recommended_claim_size: "253Gi"})
    end

    test "a growth that landed on its projection was not capped" do
      proposal = %{
        direction: :grow,
        current_claim_size: "16Gi",
        recommended_claim_size: "20Gi",
        evidence: %{"retention_floor_seconds" => 3 * @day_seconds, "median_ring_span_seconds" => 3 * @day_seconds}
      }

      refute ClaimSizing.capped_growth?(proposal)
    end

    test "a growth is measured against the ring of the region that projected it" do
      # A 16Gi region's ring projected 55Gi and the account got 55Gi. Read
      # against the account's 50Gi instead, the same evidence projects 172Gi
      # and would call the growth capped.
      proposal = %{
        direction: :grow,
        current_claim_size: "50Gi",
        recommended_claim_size: "55Gi",
        evidence: %{
          "retention_floor_seconds" => 3 * @day_seconds,
          "median_ring_span_seconds" => 94_300,
          "region_claim_size" => "16Gi"
        }
      }

      refute ClaimSizing.capped_growth?(proposal)
      assert ClaimSizing.capped_growth?(%{proposal | recommended_claim_size: "32Gi", current_claim_size: "16Gi"})

      # Raised to the account's claim from a ring that asked for 20Gi.
      raised = %{
        proposal
        | recommended_claim_size: "50Gi",
          evidence: Map.put(proposal.evidence, "median_ring_span_seconds", 3 * @day_seconds)
      }

      refute ClaimSizing.capped_growth?(raised)
    end

    test "a shrink, or evidence without a ring span, was not a capped growth" do
      refute ClaimSizing.capped_growth?(%{
               direction: :shrink,
               current_claim_size: "32Gi",
               recommended_claim_size: "16Gi",
               evidence: %{"max_occupancy_percent" => 20}
             })

      refute ClaimSizing.capped_growth?(%{
               direction: :grow,
               current_claim_size: "16Gi",
               recommended_claim_size: "32Gi",
               evidence: %{"retention_floor_seconds" => 3 * @day_seconds, "median_ring_span_seconds" => nil}
             })
    end
  end

  describe "evaluate/2 shrinking" do
    test "proposes shrinking after a long window of low occupancy" do
      # 6Gi peak at the 60% occupancy target asks for 10Gi.
      context = context(current_claim_size: "16Gi", rollups: fitting_days(30, @today))

      assert {:shrink, "10Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 30
      assert evidence["max_occupancy_percent"] == 25
    end

    test "one step never less than halves the claim" do
      rollups = fitting_days(30, @today, max_live_segment_bytes: 2 * @gibibyte)

      assert {:shrink, "8Gi", _evidence} = ClaimSizing.evaluate(context(rollups: rollups))
    end

    test "never shrinks under the validated minimum claim" do
      rollups =
        fitting_days(30, @today,
          max_live_segment_bytes: div(@gibibyte, 2),
          last_ring_budget_bytes: 6 * @gibibyte
        )

      context = context(plan: :air, current_claim_size: "8Gi", rollups: rollups)

      assert ClaimSizing.evaluate(context) == :none
    end

    test "a day without snapshots breaks the idle streak" do
      rollups =
        30
        |> fitting_days(@today)
        |> List.replace_at(15, rollup(Date.add(@today, -14), eviction_count: 0))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "an eviction inside the window breaks the idle streak" do
      rollups =
        30
        |> fitting_days(@today)
        |> List.replace_at(
          15,
          rollup(Date.add(@today, -14), snapshot_count: 96, max_occupancy_percent: 25, eviction_count: 1)
        )

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a window shorter than the shrink window withholds the proposal" do
      assert ClaimSizing.evaluate(context(rollups: fitting_days(29, @today))) == :none
    end

    test "a shrink needs its whole window after the last resize" do
      rollups = fitting_days(30, @today)

      recent = context(rollups: rollups, last_resized_at: DateTime.new!(Date.add(@today, -10), ~T[12:00:00], "Etc/UTC"))
      assert ClaimSizing.evaluate(recent) == :none

      settled = context(rollups: rollups, last_resized_at: DateTime.new!(Date.add(@today, -31), ~T[12:00:00], "Etc/UTC"))
      assert {:shrink, "10Gi", _evidence} = ClaimSizing.evaluate(settled)
    end
  end

  describe "evaluate/2 shrinking on retention" do
    # A full ring that rotates, shedding content ten days after it was
    # written: well past three retention floors, the line a day has to clear.
    defp long_retention_days(count, end_day, attrs \\ []) do
      churn_days(
        count,
        end_day,
        Keyword.merge(
          [
            eviction_count: 6,
            evicted_bytes: 4 * @gibibyte,
            median_shed_age_seconds: 10 * @day_seconds,
            median_ring_span_seconds: round(10.5 * @day_seconds),
            snapshot_count: 96,
            max_occupancy_percent: 99,
            last_ring_budget_bytes: round(44.5 * @gibibyte)
          ],
          attrs
        )
      )
    end

    defp retention_context(attrs) do
      context(Keyword.merge([plan: :enterprise, current_claim_size: "50Gi"], attrs))
    end

    test "a claim that keeps weeks of content shrinks, one step at most halving it" do
      # 50Gi keeping 10.5 days projects to about 18Gi at the floor plus
      # headroom, but one step only halves the ring.
      context = retention_context(rollups: long_retention_days(30, @today))

      assert {:shrink, "25Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["signal"] == "retention_above_floor"
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 30
      assert evidence["qualifying_threshold_seconds"] == 9 * @day_seconds
      assert evidence["shortest_shed_age_seconds"] == 10 * @day_seconds
      assert evidence["shortest_ring_span_seconds"] == round(10.5 * @day_seconds)
      assert evidence["region_claim_size"] == "50Gi"
    end

    test "the projection reads the shortest span the window saw" do
      # One day of the 100Gi region kept 12 days instead of 40: the claim has
      # to hold that day's floor too, so it is the day the target is projected
      # from. The 16Gi region lets the step go past halving, so the
      # projection is what lands: 100Gi x 3.75 days / 12 days, where the
      # median day would have asked for 10Gi.
      rollups =
        30
        |> long_retention_days(@today,
          median_shed_age_seconds: 40 * @day_seconds,
          median_ring_span_seconds: 40 * @day_seconds
        )
        |> List.replace_at(
          10,
          hd(
            long_retention_days(1, Date.add(@today, -19),
              median_shed_age_seconds: 12 * @day_seconds,
              median_ring_span_seconds: 12 * @day_seconds
            )
          )
        )

      small_region =
        30
        |> long_retention_days(@today, median_ring_span_seconds: 30 * @day_seconds)
        |> Enum.map(&Map.put(&1, :region, "eu-west"))

      context =
        retention_context(
          current_claim_size: "100Gi",
          region_claim_sizes: %{"us-east" => "100Gi", "eu-west" => "16Gi"},
          rollups: rollups ++ small_region
        )

      assert {:shrink, "32Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["shortest_ring_span_seconds"] == 12 * @day_seconds
    end

    test "never goes under the plan's starting claim" do
      rollups = long_retention_days(30, @today, median_ring_span_seconds: 40 * @day_seconds)

      assert {:shrink, "16Gi", _evidence} =
               ClaimSizing.evaluate(retention_context(current_claim_size: "20Gi", rollups: rollups))

      assert ClaimSizing.evaluate(retention_context(current_claim_size: "16Gi", rollups: rollups)) == :none

      assert {:shrink, "8Gi", _evidence} =
               ClaimSizing.evaluate(retention_context(plan: :pro, current_claim_size: "12Gi", rollups: rollups))
    end

    test "a day under three floors of retention breaks the window" do
      rollups =
        30
        |> long_retention_days(@today)
        |> List.replace_at(
          15,
          hd(long_retention_days(1, Date.add(@today, -14), median_shed_age_seconds: 8 * @day_seconds))
        )

      assert ClaimSizing.evaluate(retention_context(rollups: rollups)) == :none
    end

    test "a day without snapshots breaks the window" do
      rollups =
        30
        |> long_retention_days(@today)
        |> List.replace_at(15, hd(long_retention_days(1, Date.add(@today, -14), snapshot_count: 0)))

      assert ClaimSizing.evaluate(retention_context(rollups: rollups)) == :none
    end

    test "a day that shed nothing keeps the window but gives no span to project from" do
      quiet = [eviction_count: 0, evicted_bytes: 0, median_shed_age_seconds: nil, median_ring_span_seconds: nil]

      rollups =
        30
        |> long_retention_days(@today)
        |> List.replace_at(15, hd(long_retention_days(1, Date.add(@today, -14), quiet)))

      assert {:shrink, "25Gi", _evidence} = ClaimSizing.evaluate(retention_context(rollups: rollups))

      assert ClaimSizing.evaluate(retention_context(rollups: long_retention_days(30, @today, quiet))) == :none
    end

    test "a window shorter than a month withholds the proposal" do
      assert ClaimSizing.evaluate(retention_context(rollups: long_retention_days(29, @today))) == :none
    end

    test "days at or before the last resize measured the previous ring" do
      context =
        retention_context(
          rollups: long_retention_days(30, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -10), ~T[12:00:00], "Etc/UTC")
        )

      assert ClaimSizing.evaluate(context) == :none
    end

    test "each region projects from its own pin, and the account needs the largest" do
      # The 16Gi region keeps 14 days, the 50Gi one 30: 4.3Gi and 6.25Gi at
      # the floor plus headroom, so both sit on the plan's starting claim.
      # The step bound would stop at 25Gi, but the account already runs a
      # 16Gi ring in eu-west that keeps three floors, so that is measured
      # rather than projected and the 50Gi region lands there in one step.
      rollups =
        long_retention_days(30, @today,
          median_shed_age_seconds: 30 * @day_seconds,
          median_ring_span_seconds: 30 * @day_seconds
        ) ++
          Enum.map(
            long_retention_days(30, @today,
              median_shed_age_seconds: 14 * @day_seconds,
              median_ring_span_seconds: 14 * @day_seconds,
              last_ring_budget_bytes: round(12.5 * @gibibyte)
            ),
            &Map.put(&1, :region, "eu-west")
          )

      context =
        retention_context(
          rollups: rollups,
          region_claim_sizes: %{"us-east" => "50Gi", "eu-west" => "16Gi"}
        )

      assert {:shrink, "16Gi", _evidence} = ClaimSizing.evaluate(context)
    end

    test "a smaller region that only never filled does not lower the step bound" do
      # An 8Gi runner cache that never filled says nothing about how much of
      # the account's rotating content a ring has to hold.
      rollups =
        long_retention_days(30, @today) ++
          Enum.map(fitting_days(30, @today, max_live_segment_bytes: @gibibyte), &Map.put(&1, :region, "eu-west"))

      context =
        retention_context(
          rollups: rollups,
          region_claim_sizes: %{"us-east" => "50Gi", "eu-west" => "8Gi"}
        )

      assert {:shrink, "25Gi", _evidence} = ClaimSizing.evaluate(context)
    end

    test "a region still short of three floors blocks the account's shrink" do
      rollups =
        long_retention_days(30, @today) ++
          Enum.map(
            long_retention_days(30, @today, median_shed_age_seconds: 5 * @day_seconds),
            &Map.put(&1, :region, "eu-west")
          )

      assert ClaimSizing.evaluate(retention_context(rollups: rollups)) == :none
    end
  end

  describe "evaluate/2 with regions pinned apart" do
    # An enterprise account whose us-east instance kept the 50Gi claim the
    # pin migration grandfathered, and whose later expansion to ap-southeast
    # was built at 16Gi.
    defp mixed_context(attrs) do
      context(
        Keyword.merge(
          [
            plan: :enterprise,
            current_claim_size: "50Gi",
            region_claim_sizes: %{"us-east" => "50Gi", "ap-southeast" => "16Gi"}
          ],
          attrs
        )
      )
    end

    defp in_region(rollups, region), do: Enum.map(rollups, &Map.put(&1, :region, region))

    test "a small region's shortfall is scaled from its own ring, not the account's largest pin" do
      # The readings production recorded on a 16Gi instance: a 12.5 GiB ring
      # shedding at 20.9 hours and cycling 4.6 rings over two days. Scaled
      # from the 50Gi the account's other regions hold, that proposed 200Gi.
      ring_bytes = 13_421_772_800

      rollups =
        2
        |> churn_days(@today,
          median_shed_age_seconds: 75_068,
          median_ring_span_seconds: 94_300,
          evicted_bytes: round(2.3 * ring_bytes),
          last_ring_budget_bytes: ring_bytes
        )
        |> in_region("ap-southeast")

      assert {:grow, "55Gi", evidence} = ClaimSizing.evaluate(mixed_context(rollups: rollups))
      assert evidence["region"] == "ap-southeast"
      assert evidence["region_claim_size"] == "16Gi"
      assert evidence["ring_turnover"] == 4.6
    end

    test "a small region short of the floor is raised to the account's claim" do
      # 16Gi keeping 3 days projects 20Gi, under the 50Gi the rest of the
      # account holds. The answer is that claim, not a step clamped away.
      rollups = 14 |> marginal_churn(@today) |> in_region("ap-southeast")

      assert {:grow, "50Gi", evidence} = ClaimSizing.evaluate(mixed_context(rollups: rollups))
      assert evidence["region"] == "ap-southeast"
      assert evidence["region_claim_size"] == "16Gi"
    end

    test "a small region whose projection lands under its own pin is still raised" do
      # A span well past the floor with a shed age just under it projects
      # below the 16Gi the region holds; clamped against the account's claim
      # that read as no change and the region stayed short forever.
      rollups = 14 |> churn_at(@today, 250_000, 330_000) |> in_region("ap-southeast")

      assert {:grow, "50Gi", _evidence} = ClaimSizing.evaluate(mixed_context(rollups: rollups))
    end

    test "a region at the account's claim that projects no growth proposes nothing" do
      rollups = churn_at(14, @today, 250_000, 330_000)

      assert ClaimSizing.evaluate(mixed_context(rollups: rollups)) == :none
    end

    test "a small region's growth past the account's claim is bounded by its own step" do
      # Two confirmed days of severe shedding take four times the ring they
      # measured: 64Gi, not four times the account's 50Gi.
      rollups = 2 |> severe_churn(@today) |> in_region("ap-southeast")

      assert {:grow, "64Gi", _evidence} = ClaimSizing.evaluate(mixed_context(rollups: rollups))
    end

    test "raising a small region never passes the plan's ceiling" do
      rollups = 14 |> marginal_churn(@today) |> in_region("ap-southeast")

      context =
        mixed_context(
          plan: :pro,
          current_claim_size: "100Gi",
          region_claim_sizes: %{"us-east" => "100Gi", "ap-southeast" => "16Gi"},
          rollups: rollups
        )

      assert ClaimSizing.evaluate(context) == :none
    end
  end

  describe "evaluate/2 across regions" do
    test "a growing region wins over a shrinking one" do
      rollups =
        moderate_churn(14, @today) ++ Enum.map(fitting_days(30, @today), &Map.put(&1, :region, "eu-west"))

      assert {:grow, "40Gi", evidence} = ClaimSizing.evaluate(context(rollups: rollups))
      assert evidence["region"] == "us-east"
    end

    test "shrinking needs every region with data to agree" do
      rollups =
        fitting_days(30, @today) ++
          Enum.map(churn_days(5, @today, median_shed_age_seconds: 5 * @day_seconds), &Map.put(&1, :region, "eu-west"))

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
