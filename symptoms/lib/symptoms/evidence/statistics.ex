defmodule Symptoms.Evidence.Statistics do
  @moduledoc """
  Raw per-window statistics (`symptoms/README.md` "Inputs"). Every statistic
  is oriented so that larger means worse; `Symptoms.Evidence.Calibration`
  ranks it against the stream's own null history, so none of these needs to
  be a calibrated likelihood ratio.

  - Error counts (traces): `fit_beta_binomial/1` on the trailing 28 days, then
    `beta_binomial_residual/3` per window.
  - Event counts (error issues, Kubernetes events, log templates):
    `fit_negative_binomial/1` then `negative_binomial_residual/2`.
  - Metrics: `robust_residual/3` (median/MAD) against `hour_of_week_baseline/3`.
  - Latency: log-bucket histograms with γ = 1.1 (`bucket_index/1`,
    `histogram/1`) and `latency_exceedance/3`, the share of the window above a
    baseline quantile bucket.
  """

  alias Symptoms.Evidence.Calibration

  @gamma 1.1
  # ceil(ln(60_000 ms) / ln(1.1)) = ceil(115.43): bucket 116 holds 60 s and above.
  @max_bucket 116
  # 1 / Φ⁻¹(3/4): makes the MAD a consistent estimate of a normal σ.
  @mad_scale 1.4826
  # sqrt(π/2): the same for the mean absolute deviation.
  @mean_abs_scale 1.2533

  @type beta_binomial_fit :: %{p: float(), rho: float()}
  @type negative_binomial_fit :: %{mean: float(), alpha: float(), n: non_neg_integer()}
  @type histogram :: %{non_neg_integer() => non_neg_integer()}
  @type exceedance :: %{
          bucket: non_neg_integer(),
          exceeding: non_neg_integer(),
          n: non_neg_integer(),
          observed: float(),
          expected: float()
        }

  @doc """
  Fits a beta-binomial null to `[{errors, total}]` windows by the method of
  moments.

  `p` is the pooled error share. `rho` is the intra-window correlation that
  makes `Var(x_i) = n_i p (1 - p) (1 + (n_i - 1) rho)` match the observed
  between-window variance:

      rho = (Σ (x_i - n_i p)² / (p (1 - p)) - Σ n_i) / Σ n_i (n_i - 1)

  clamped to `0..1` (underdispersed history falls back to the binomial).
  When the history has no errors, or only errors, `p` is smoothed to
  `(errors + 0.5) / (total + 1)` so the variance stays positive.
  """
  @spec fit_beta_binomial([{non_neg_integer(), non_neg_integer()}]) :: beta_binomial_fit()
  def fit_beta_binomial(history) do
    windows = Enum.filter(history, fn {_errors, total} -> total > 0 end)
    errors = windows |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    total = windows |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    p = smoothed_share(errors, total)

    %{p: p, rho: overdispersion(windows, p)}
  end

  defp smoothed_share(errors, total) when errors > 0 and errors < total, do: errors / total
  defp smoothed_share(errors, total), do: (errors + 0.5) / (total + 1)

  defp overdispersion(windows, p) do
    pairs = windows |> Enum.map(fn {_x, n} -> n * (n - 1) end) |> Enum.sum()
    totals = windows |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    squares = windows |> Enum.map(fn {x, n} -> (x - n * p) ** 2 end) |> Enum.sum()

    if pairs == 0 do
      0.0
    else
      ((squares / (p * (1 - p)) - totals) / pairs) |> max(0.0) |> min(1.0)
    end
  end

  @doc """
  The standardized residual of `errors` out of `total` requests against a
  `fit_beta_binomial/1` fit: `(x - n p) / sqrt(n p (1 - p) (1 + (n - 1) rho))`.
  A window without requests has residual `0.0`.
  """
  @spec beta_binomial_residual(non_neg_integer(), non_neg_integer(), beta_binomial_fit()) :: float()
  def beta_binomial_residual(_errors, 0, _fit), do: 0.0

  def beta_binomial_residual(errors, total, %{p: p, rho: rho}) do
    variance = total * p * (1 - p) * (1 + (total - 1) * rho)
    (errors - total * p) / :math.sqrt(variance)
  end

  @doc """
  Fits a negative binomial null to a list of per-window counts by the method
  of moments: `Var = μ + α μ²`, so `α = max(0, (s² - μ) / μ²)` with the
  sample variance `s²` (denominator `n - 1`). Fewer than two windows, or a
  zero mean, give `α = 0` (Poisson).
  """
  @spec fit_negative_binomial([non_neg_integer()]) :: negative_binomial_fit()
  def fit_negative_binomial([]), do: %{mean: 0.0, alpha: 0.0, n: 0}

  def fit_negative_binomial(counts) do
    n = length(counts)
    mean = Enum.sum(counts) / n

    alpha =
      if n > 1 and mean > 0 do
        variance = (counts |> Enum.map(&((&1 - mean) ** 2)) |> Enum.sum()) / (n - 1)
        max(0.0, (variance - mean) / mean ** 2)
      else
        0.0
      end

    %{mean: mean, alpha: alpha, n: n}
  end

  @doc """
  The standardized residual of `count` against a `fit_negative_binomial/1`
  fit: `(x - μ) / sqrt(μ + α μ²)`. A zero mean is floored at `1 / (n + 1)`
  (one pseudo-event over the history and this window), so a first event on a
  quiet stream gives a large but finite residual.
  """
  @spec negative_binomial_residual(non_neg_integer(), negative_binomial_fit()) :: float()
  def negative_binomial_residual(count, %{mean: mean, alpha: alpha, n: n}) do
    mu = max(mean, 1 / (n + 1))
    (count - mu) / :math.sqrt(mu + alpha * mu * mu)
  end

  @doc """
  The values of `windows` at the same hour of week as `at`, from the trailing
  28 days, excluding windows with an open symptom. Same window shape and
  options as `Symptoms.Evidence.Calibration.null_history/3`, with the metric
  value in `:statistic`.
  """
  @spec hour_of_week_baseline([Calibration.window()], DateTime.t(), keyword()) :: [number()]
  def hour_of_week_baseline(windows, at, opts \\ []), do: Calibration.null_history(windows, at, opts)

  @doc """
  Robust residual `(x - median) / scale` against a baseline, where `scale` is
  `1.4826 × MAD`. When the MAD is zero (more than half the baseline equal),
  it falls back to `1.2533 ×` the mean absolute deviation, then to the
  `:min_scale` option (default `1.0`). An empty baseline gives `0.0`.
  """
  @spec robust_residual(number(), [number()], keyword()) :: float()
  def robust_residual(value, baseline, opts \\ [])
  def robust_residual(_value, [], _opts), do: 0.0

  def robust_residual(value, baseline, opts) do
    center = median(baseline)
    deviations = Enum.map(baseline, &abs(&1 - center))
    (value - center) / robust_scale(deviations, Keyword.get(opts, :min_scale, 1.0))
  end

  defp robust_scale(deviations, min_scale) do
    mad = median(deviations)
    mean_abs = Enum.sum(deviations) / length(deviations)

    cond do
      mad > 0 -> @mad_scale * mad
      mean_abs > 0 -> @mean_abs_scale * mean_abs
      true -> min_scale
    end
  end

  @doc "The median of a non-empty list."
  @spec median([number()]) :: number()
  def median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle)
    else
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end
  end

  @doc """
  The log bucket (γ = #{@gamma}) for a latency in milliseconds. Bucket `i`
  holds `(γ^(i-1), γ^i]` ms; bucket 0 holds everything up to 1 ms and bucket
  #{@max_bucket} everything above `γ^#{@max_bucket - 1}` ms (about 57.6 s, so
  it includes 60 s).
  """
  @spec bucket_index(number()) :: non_neg_integer()
  def bucket_index(ms) when ms <= 1, do: 0

  def bucket_index(ms) do
    # The epsilon keeps exact powers of γ in their own bucket despite rounding.
    min(ceil(:math.log(ms) / :math.log(@gamma) - 1.0e-9), @max_bucket)
  end

  @doc "The upper bound in milliseconds of bucket `index`: `γ^index`."
  @spec bucket_upper_bound(non_neg_integer()) :: float()
  def bucket_upper_bound(index), do: :math.pow(@gamma, index)

  @doc "Builds a histogram (`%{bucket => count}`) from latencies in milliseconds."
  @spec histogram([number()]) :: histogram()
  def histogram(latencies_ms), do: Enum.frequencies_by(latencies_ms, &bucket_index/1)

  @doc "Adds histograms bucket by bucket, for example 28 days of 5-minute windows."
  @spec merge_histograms([histogram()]) :: histogram()
  def merge_histograms(histograms) do
    Enum.reduce(histograms, %{}, fn histogram, acc ->
      Map.merge(acc, histogram, fn _bucket, a, b -> a + b end)
    end)
  end

  @doc """
  The smallest bucket whose cumulative count reaches `q` of the total, or
  `nil` for an empty histogram.
  """
  @spec quantile_bucket(histogram(), float()) :: non_neg_integer() | nil
  def quantile_bucket(histogram, q) do
    total = histogram |> Map.values() |> Enum.sum()

    if total == 0 do
      nil
    else
      histogram
      |> Enum.sort()
      |> Enum.reduce_while(0, &quantile_step(&1, &2, q * total))
    end
  end

  defp quantile_step({bucket, count}, cumulative, target) when cumulative + count >= target, do: {:halt, bucket}
  defp quantile_step({_bucket, count}, cumulative, _target), do: {:cont, cumulative + count}

  @doc "`{count in buckets strictly above bucket, total count}`."
  @spec exceedance(histogram(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  def exceedance(histogram, bucket) do
    above = histogram |> Enum.filter(fn {b, _} -> b > bucket end) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {above, histogram |> Map.values() |> Enum.sum()}
  end

  @doc """
  The latency statistic: the share of the window's requests above the
  baseline's `q` quantile bucket (the README uses `q = 0.95` and `q = 0.5`).

  `expected` is the baseline's own share above that bucket (at most `1 - q`,
  less when the quantile falls inside a bucket). `exceeding` and `n` can be
  fed to `beta_binomial_residual/3` with a fit over the stream's history of
  exceedances. Returns `nil` when the baseline is empty.
  """
  @spec latency_exceedance(histogram(), histogram(), float()) :: exceedance() | nil
  def latency_exceedance(window, baseline, q) do
    case quantile_bucket(baseline, q) do
      nil ->
        nil

      bucket ->
        {exceeding, n} = exceedance(window, bucket)
        {baseline_above, baseline_total} = exceedance(baseline, bucket)

        %{
          bucket: bucket,
          exceeding: exceeding,
          n: n,
          observed: if(n == 0, do: 0.0, else: exceeding / n),
          expected: baseline_above / baseline_total
        }
    end
  end
end
