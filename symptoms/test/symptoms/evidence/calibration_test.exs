defmodule Symptoms.Evidence.CalibrationTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Calibration
  alias Symptoms.Evidence.Statistics

  describe "conformal p-value" do
    test "counts history values at or above the statistic" do
      # #{>= 5} in [1, 5, 7, 3] = 2 → (1 + 2) / (1 + 4)
      assert Calibration.conformal_p_value(5, [1, 5, 7, 3]) == 0.6
      assert Calibration.conformal_p_value(100, Enum.to_list(1..99)) == 0.01
      assert Calibration.conformal_p_value(5, []) == 1.0
    end
  end

  describe "null history" do
    # Monday 10:00 UTC.
    @at ~U[2026-11-16 10:00:00Z]

    test "keeps the trailing 28 days at the same hour of week without open symptoms" do
      windows = [
        %{window_start: DateTime.shift(@at, week: -1), statistic: 1},
        %{window_start: DateTime.shift(@at, week: -4), statistic: 2},
        %{window_start: DateTime.shift(@at, week: -2), statistic: 3, open_symptom: true},
        %{window_start: DateTime.shift(@at, week: -5), statistic: 4},
        %{window_start: DateTime.shift(@at, day: -6), statistic: 5},
        %{window_start: DateTime.shift(@at, second: -7 * 86_400 + 3600), statistic: 6},
        %{window_start: @at, statistic: 7},
        %{window_start: DateTime.shift(@at, second: -21 * 86_400 + 59 * 60), statistic: 8}
      ]

      assert Enum.sort(Calibration.null_history(windows, @at)) == [1, 2, 8]
      assert Statistics.hour_of_week_baseline(windows, @at) == Calibration.null_history(windows, @at)
      # (1 + #{>= 2 in [1, 2, 8]}) / 4
      assert Calibration.p_value(2, @at, windows) == 0.75
    end

    test "hour of week starts on Monday" do
      assert Calibration.hour_of_week(~U[2026-11-16 00:00:00Z]) == 0
      assert Calibration.hour_of_week(~U[2026-11-22 23:30:00Z]) == 167
    end
  end

  describe "p-to-e calibrators" do
    test "power calibrator κ p^(κ-1) at chosen p" do
      # 0.5 · 0.25^-0.5 = 0.5 · 2
      assert_in_delta Calibration.e_value(0.25), 1.0, 1.0e-12
      # 0.5 · 0.01^-0.5 = 0.5 · 10
      assert_in_delta Calibration.e_value(0.01), 5.0, 1.0e-12
      assert_in_delta Calibration.e_value(1.0), 0.5, 1.0e-12
      # 0.2 · 32^0.8 = 0.2 · 16
      assert_in_delta Calibration.e_value(1 / 32, kappa: 0.2), 3.2, 1.0e-12
    end

    test "mixture calibrator at chosen p" do
      # p = 1/e: (1 - 1/e - 1/e) / (1/e) = e - 2
      assert_in_delta Calibration.e_value(:math.exp(-1), calibrator: :mixture), :math.exp(1) - 2, 1.0e-12
      assert_in_delta Calibration.e_value(1.0, calibrator: :mixture), 0.5, 1.0e-12
      # Continuous at the cancellation guard.
      assert_in_delta Calibration.mixture_calibrator(1 - 2.0e-6), 0.5, 1.0e-5
    end

    test "e-values are capped at 20" do
      # Uncapped 0.5 · 0.0001^-0.5 = 50.
      assert Calibration.e_value(0.0001) == 20.0
      assert Calibration.e_value(1.0e-12, calibrator: :mixture) == 20.0
      assert Calibration.e_value(0.0) == 20.0
    end

    test "a uniform p gives an e-value with mean at most 1" do
      # Power: the cap binds below p* = (20/0.5)^-2 = 1/1600, so
      # E = 20/1600 + (1 - sqrt(1/1600)) = 0.0125 + 0.975 = 0.9875.
      assert_in_delta integrate(&Calibration.e_value/1), 0.9875, 1.0e-3
      # Mixture: uncapped it integrates to 1, but near 0 it behaves like
      # 1 / (p ln² p), which reaches 20 at p* ≈ 0.00105 (p* ln² p* = 0.05).
      # The cap removes ∫₀^p* 1/(p ln² p) dp - 20 p* = 1/|ln p*| - 0.021
      # ≈ 0.146 - 0.021 = 0.125, so E ≈ 0.875.
      mixture = integrate(&Calibration.e_value(&1, calibrator: :mixture))
      assert mixture <= 1.0
      assert_in_delta mixture, 0.875, 0.01
    end

    test "a discrete conformal p-value also gives mean at most 1" do
      # p takes k/(n+1), k = 1..n+1, uniformly under exchangeability.
      n = 99
      mean = Enum.sum(for k <- 1..(n + 1), do: Calibration.e_value(k / (n + 1))) / (n + 1)

      assert mean <= 1.0
    end
  end

  # Midpoint rule over (0, 1]; the capped integrand is bounded by 20.
  defp integrate(f) do
    steps = 200_000
    Enum.sum(for i <- 0..(steps - 1), do: f.((i + 0.5) / steps)) / steps
  end
end
