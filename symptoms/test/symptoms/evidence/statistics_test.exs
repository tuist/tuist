defmodule Symptoms.Evidence.StatisticsTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Statistics

  describe "beta-binomial" do
    test "fits the between-window variance by the method of moments" do
      # errors 10 / 200 → p = 0.05, p(1-p) = 0.0475.
      # Σ (x - n p)² = (1-5)² + (9-5)² = 32; 32 / 0.0475 = 673.684.
      # rho = (673.684 - 200) / (2 · 100 · 99) = 473.684 / 19800 = 0.0239234.
      fit = Statistics.fit_beta_binomial([{1, 100}, {9, 100}])

      assert_in_delta fit.p, 0.05, 1.0e-12
      assert_in_delta fit.rho, 473.684_210_5 / 19_800, 1.0e-9
    end

    test "residual uses the overdispersed variance" do
      fit = Statistics.fit_beta_binomial([{1, 100}, {9, 100}])

      # Var = 100 · 0.0475 · (1 + 99 rho) = 4.75 · (1 + 473.684/200) = 16 → sd 4.
      assert_in_delta Statistics.beta_binomial_residual(15, 100, fit), (15 - 5) / 4, 1.0e-9
    end

    test "underdispersed history falls back to the binomial" do
      fit = Statistics.fit_beta_binomial([{5, 100}, {5, 100}])

      assert fit.rho == 0.0
      assert_in_delta Statistics.beta_binomial_residual(15, 100, fit), 10 / :math.sqrt(4.75), 1.0e-9
    end

    test "history without errors is smoothed so the variance stays positive" do
      fit = Statistics.fit_beta_binomial([{0, 100}, {0, 100}])

      # (0 + 0.5) / (200 + 1)
      assert_in_delta fit.p, 0.5 / 201, 1.0e-12
      assert Statistics.beta_binomial_residual(3, 100, fit) > 0
    end

    test "an empty window has residual zero" do
      assert Statistics.beta_binomial_residual(0, 0, %{p: 0.1, rho: 0.0}) == 0.0
    end
  end

  describe "negative binomial" do
    test "fits alpha by the method of moments" do
      # mean 5, s² = (9 + 1 + 1 + 9) / 3 = 20/3, alpha = (20/3 - 5) / 25 = 1/15.
      fit = Statistics.fit_negative_binomial([2, 4, 6, 8])

      assert fit.mean == 5.0
      assert_in_delta fit.alpha, 1 / 15, 1.0e-12
      # sd = sqrt(5 + 25/15) = sqrt(20/3)
      assert_in_delta Statistics.negative_binomial_residual(15, fit), 10 / :math.sqrt(20 / 3), 1.0e-9
    end

    test "underdispersed counts are Poisson" do
      fit = Statistics.fit_negative_binomial([5, 5, 5])

      assert fit.alpha == 0.0
      assert_in_delta Statistics.negative_binomial_residual(9, fit), 4 / :math.sqrt(5), 1.0e-12
    end

    test "a zero mean is floored at one pseudo-event" do
      fit = Statistics.fit_negative_binomial([0, 0, 0])

      # mu = 1 / (3 + 1) = 0.25 → (1 - 0.25) / 0.5
      assert_in_delta Statistics.negative_binomial_residual(1, fit), 1.5, 1.0e-12
    end
  end

  describe "robust residual" do
    test "uses the median and the scaled MAD" do
      # median 3; deviations [2, 1, 0, 1, 97] → MAD 1 → scale 1.4826.
      assert_in_delta Statistics.robust_residual(6, [1, 2, 3, 4, 100]), 3 / 1.4826, 1.0e-9
    end

    test "falls back to the mean absolute deviation when the MAD is zero" do
      # median 5; deviations [0, 0, 0, 0, 4]; mean 0.8 → scale 1.2533 · 0.8.
      assert_in_delta Statistics.robust_residual(7, [5, 5, 5, 5, 9]), 2 / (1.2533 * 0.8), 1.0e-9
    end

    test "a constant baseline uses the minimum scale" do
      assert Statistics.robust_residual(7, [5, 5, 5], min_scale: 2.0) == 1.0
      assert Statistics.robust_residual(7, []) == 0.0
    end

    test "median of an even list averages the middle values" do
      assert Statistics.median([4, 1, 3, 2]) == 2.5
    end
  end

  describe "log-bucket latency histograms" do
    test "bucket i holds (1.1^(i-1), 1.1^i] ms" do
      assert Statistics.bucket_index(0.4) == 0
      assert Statistics.bucket_index(1) == 0
      assert Statistics.bucket_index(1.05) == 1
      assert Statistics.bucket_index(1.1) == 1
      assert Statistics.bucket_index(1.11) == 2
      assert Statistics.bucket_index(1.21) == 2
      # ln(50000) / ln(1.1) = 113.52
      assert Statistics.bucket_index(50_000) == 114
    end

    test "about 115 buckets cover 1 ms to 60 s and larger values share the last" do
      # ln(60000) / ln(1.1) = 115.43
      assert Statistics.bucket_index(60_000) == 116
      assert Statistics.bucket_index(1.0e9) == 116
      # 1.1^115 = e^(115 · 0.0953102) = e^10.96067 ≈ 57_565 ms
      assert_in_delta Statistics.bucket_upper_bound(115), 57_565, 1
    end

    test "exceedance share above the baseline p95 bucket" do
      baseline = %{10 => 95, 20 => 5}
      window = %{10 => 80, 20 => 20}

      assert %{bucket: 10, exceeding: 20, n: 100, observed: 0.2, expected: 0.05} =
               Statistics.latency_exceedance(window, baseline, 0.95)
    end

    test "quantile bucket is the first reaching the cumulative share" do
      baseline = Statistics.histogram([0.5, 1.05, 1.15, 1.15, 2.0])

      # buckets 0:1, 1:1, 2:2, 8:1 (ln 2 / ln 1.1 = 7.27)
      assert baseline == %{0 => 1, 1 => 1, 2 => 2, 8 => 1}
      assert Statistics.quantile_bucket(baseline, 0.5) == 2
      assert Statistics.quantile_bucket(baseline, 0.95) == 8
      assert Statistics.latency_exceedance(%{}, %{}, 0.95) == nil
    end

    test "merges histograms bucket by bucket" do
      assert Statistics.merge_histograms([%{1 => 2}, %{1 => 3, 4 => 1}]) == %{1 => 5, 4 => 1}
    end
  end
end
