defmodule Symptoms.Evidence.ThresholdTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Threshold

  test "five quiet windows resolve an open detector even while its CUSUM is positive" do
    cap = :math.log(20)
    xs = [cap] ++ List.duplicate(0.0, 5) ++ [cap] ++ List.duplicate(0.0, 1433)
    assert Threshold.crossings([xs], cap, 0.0) == 2
    choice = Threshold.choose([xs], 1)
    assert choice.h > cap
    assert choice.crossings == 1
    assert Threshold.crossings([xs], choice.h, 0.0) == choice.crossings
  end

  test "quiet windows reset only an open detector; zero CUSUM alone does not resolve it" do
    assert Threshold.crossings([[3.0, 0, -0.01, 0, -0.01, 0, 3.0]], 3.0, 0.0) == 2
    assert Threshold.crossings([[3.0, -10, 3.0]], 3.0, 0.0) == 1
    # At h=4 the first burst did not open, so the five quiet windows must
    # not discard its accumulated score. The second burst then opens once.
    assert Threshold.crossings([[3.0, 0, 0, 0, 0, 0, 3.0]], 4.0, 0.0) == 1
    assert Threshold.crossings([[3.0, 0, 0, 0, 0, 0, 3.0]], 7.0, 0.0) == 0
    # Drift changes the score, not the definition of a quiet observation.
    assert Threshold.crossings([[3.0, 0.01, 0.01, 0.01, 0.01, 0.01, 3.0]], 2.5, 0.1) == 1
    assert Threshold.crossings([[3.0, 0, 0, 0, 3.0]], 3.0, 0.0, resolve_after_quiet_windows: 3) == 2
  end

  test "threshold response summaries match direct replay between all sampled boundaries" do
    for a <- [-2.0, 0.0, 1.0, 3.0], b <- [1.0, 3.0], c <- [1.0, 3.0], quiet <- [1, 5, 6], drift <- [-0.1, 0.0, 0.1] do
      xs = [a] ++ List.duplicate(0.0, quiet) ++ [b, -0.01, c] ++ List.duplicate(0.0, 5) ++ [3.0]
      {steps, _} = Threshold.summary(xs, drift, 0.5)

      for h <- Enum.map(1..24, &(&1 / 2)) ++ Enum.map(steps, &elem(&1, 0)) do
        {_threshold, summarized} = steps |> Enum.take_while(&(elem(&1, 0) <= h)) |> List.last()
        assert summarized == Threshold.crossings([xs], h, drift), inspect({xs, drift, h, steps})
      end
    end
  end

  test "excursion peaks are counted once per excursion" do
    # S: 1, 2, 0, 2, 2.5, 0, 1
    assert Threshold.excursion_peaks([1, 1, -5, 2, 0.5, -10, 1], 0.0) == [2.0, 2.5, 1.0]
  end

  # One entity-day of 1-minute windows with four excursions peaking at 6, 5, 4, 3.
  defp quiet_day do
    spikes = %{100 => 6, 400 => 5, 700 => 4, 1000 => 3}
    for i <- 0..1439, do: Map.get(spikes, i, -1)
  end

  test "chooses the smallest h meeting the budget" do
    choice = Threshold.choose([quiet_day()], 2)

    # Two crossings allowed: h must exceed the third peak (4), keeping 6 and 5.
    assert choice.h > 4.0
    assert_in_delta choice.h, 4.0, 1.0e-6
    assert choice.crossings == 2
    assert choice.entity_days == 1.0
    assert choice.rate == 2.0
    # At h = 4 itself the rate would break the budget.
    assert Threshold.crossings([quiet_day()], 4.0, 0.0) == 3
  end

  test "rates are per entity-day across entities" do
    # Two entity-days, budget 1 per entity-day → two crossings allowed.
    choice = Threshold.choose([quiet_day(), quiet_day()], 1)

    assert choice.entity_days == 2.0
    # Peaks sorted: 6, 6, 5, 5, ... → third is 5.
    assert_in_delta choice.h, 5.0, 1.0e-6
    assert choice.crossings == 2
  end

  test "a summary retains threshold-dependent counts and the window denominator" do
    xs = [3.0, 0, 0, 0, 0, 0, 3.0]
    assert {steps, 7} = Threshold.summary(xs, 0.0, 3.0)
    assert [{3.0, 2}, {one_h, 1}, {zero_h, 0}] = steps
    assert one_h > 3.0 and one_h < 6.0
    assert zero_h > 6.0
    for {h, count} <- steps, do: assert(Threshold.crossings([xs], h, 0.0) == count)
    assert {_, 1440} = Threshold.summary(quiet_day(), 0.0, :math.log(20))
  end

  test "choosing from summaries matches choosing from the series" do
    series = [quiet_day(), quiet_day(), [1, 1, -5, 2, 0.5, -10, 1]]
    summaries = Enum.map(series, &Threshold.summary(&1, 0.0, :math.log(20)))

    for budget <- [0, 1, 2, 10] do
      assert Threshold.choose_summaries(summaries, budget) == Threshold.choose(series, budget)
    end

    # Budget 1 over (2 · 1440 + 7) · 60 / 86 400 = 2.0049 entity-days allows
    # 2 crossings: peaks 6, 6, 5, 5, … → h just above 5.
    assert_in_delta Threshold.choose_summaries(summaries, 1).h, 5.0, 1.0e-6
  end

  test "a zero budget sits above the largest peak; a loose one stops at the floor" do
    assert Threshold.choose([quiet_day()], 0).crossings == 0

    loose = Threshold.choose([quiet_day()], 10)
    assert loose.h == :math.log(20)
    # Peaks 6, 5, 4, 3 all reach ln 20 = 2.996.
    assert loose.crossings == 4
  end
end
