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
    Map.merge(
      %{
        plan: :pro,
        current_claim_size: "30Gi",
        rollups: [],
        last_resized_at: nil,
        today: @today
      },
      Map.new(attrs)
    )
  end

  describe "evaluate/2 growth" do
    test "proposes growth after a sustained streak of churn under the retention floor" do
      # Pro floor is 3 days; the ring holds 1.5 days, so the projection asks
      # for 2x with headroom on top, and the step and ceiling clamps bite.
      context = context(rollups: churn_days(14, @today))

      assert {:grow, "50Gi", evidence} = ClaimSizing.evaluate(context)
      assert evidence["region"] == "us-east"
      assert evidence["window_days"] == 14
      assert evidence["median_shed_age_seconds"] == 12 * 3_600
      assert evidence["retention_floor_seconds"] == 3 * @day_seconds
    end

    test "the streak may end yesterday, so a quiet partial day does not break it" do
      rollups = churn_days(14, Date.add(@today, -1)) ++ [rollup(@today, snapshot_count: 4, max_occupancy_percent: 95)]

      assert {:grow, "50Gi", _evidence} = ClaimSizing.evaluate(context(rollups: rollups))
    end

    test "one day without evictions inside the window withholds the proposal" do
      rollups =
        14
        |> churn_days(@today)
        |> List.replace_at(7, rollup(Date.add(@today, -6), snapshot_count: 96, max_occupancy_percent: 95))

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
    end

    test "a streak shorter than the window withholds the proposal" do
      assert ClaimSizing.evaluate(context(rollups: churn_days(13, @today))) == :none
    end

    test "shed age at or above the floor is not churn" do
      rollups = churn_days(14, @today, median_shed_age_seconds: 4 * @day_seconds)

      assert ClaimSizing.evaluate(context(rollups: rollups)) == :none
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
      context = context(plan: :enterprise, current_claim_size: "50Gi", rollups: churn_days(14, @today))

      assert ClaimSizing.evaluate(context) == :none
    end

    test "a recent resize cools the account down" do
      context =
        context(
          rollups: churn_days(14, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -10), ~T[00:00:00], "Etc/UTC")
        )

      assert ClaimSizing.evaluate(context) == :none
    end

    test "the cooldown expires" do
      context =
        context(
          rollups: churn_days(14, @today),
          last_resized_at: DateTime.new!(Date.add(@today, -31), ~T[00:00:00], "Etc/UTC")
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
  end

  describe "evaluate/2 across regions" do
    test "a growing region wins over a shrinking one" do
      rollups =
        churn_days(14, @today) ++ Enum.map(idle_days(90, @today), &Map.put(&1, :region, "eu-central"))

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
