defmodule Symptoms.Evidence.VersionTest do
  @moduledoc """
  Version-against-version anytime-valid test on error share (README
  "Deploys"), a mixture sequential probability ratio test.

  In one window the new version has `x_new` errors in `n_new` requests and
  the reference version `x_old` in `n_old`. Conditional on the `k = x_new +
  x_old` errors, if both versions have the same error rate, `x_new` is
  `Binomial(k, π₀)` with `π₀ = n_new / (n_new + n_old)` (exact for Poisson
  counts, close for binomial counts at small error shares). Under an odds
  ratio `ψ > 1` the share is `θ = ψ π₀ / (ψ π₀ + 1 - π₀)`, and

      LR_ψ = (θ / π₀)^x_new · ((1 - θ) / (1 - π₀))^(k - x_new)

  has conditional mean 1 under the null. The product over windows of each
  `LR_ψ` is a test martingale, so the equal-weight mixture over the grid
  #{inspect([1.5, 2.0, 3.0, 5.0, 10.0])} is an e-process: rejecting when it
  reaches `1/α` keeps the type I error at most `α` however long it runs.
  """

  alias Symptoms.Evidence.Statistics

  @grid [1.5, 2.0, 3.0, 5.0, 10.0]

  @doc "The odds-ratio grid."
  @spec grid() :: [float()]
  def grid, do: @grid

  @doc "The starting log weights (all zero: every mixture component at 1)."
  @spec initial() :: [float()]
  def initial, do: Enum.map(@grid, fn _ -> 0.0 end)

  @doc """
  The log likelihood ratio of each grid component for one window. A window
  where either version served nothing, or with no errors, is uninformative
  (all zeros).
  """
  @spec window_log_lrs(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: [float()]
  def window_log_lrs(x_new, n_new, x_old, n_old) do
    k = x_new + x_old

    if n_new == 0 or n_old == 0 or k == 0 do
      initial()
    else
      pi0 = n_new / (n_new + n_old)

      Enum.map(@grid, fn psi ->
        theta = psi * pi0 / (psi * pi0 + 1 - pi0)
        x_new * :math.log(theta / pi0) + (k - x_new) * :math.log((1 - theta) / (1 - pi0))
      end)
    end
  end

  @doc "Adds one window to the running log weights."
  @spec update([float()], non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: [float()]
  def update(log_weights, x_new, n_new, x_old, n_old) do
    log_weights
    |> Enum.zip(window_log_lrs(x_new, n_new, x_old, n_old))
    |> Enum.map(fn {a, b} -> a + b end)
  end

  @doc """
  The mixture e-value, saturating at the largest finite float on overflow
  (and zero on underflow). Use `log_e_value/1` for scoring and rejection;
  this compatibility representation must not be logged or accumulated.
  """
  @spec e_value([float()]) :: float()
  def e_value(log_weights), do: :math.exp(min(log_e_value(log_weights), :math.log(1.797_693_134_862_315_7e308)))

  @doc "The log mixture e-value, computed with log-sum-exp without exponentiating the result."
  @spec log_e_value([float()]) :: float()
  def log_e_value(log_weights) do
    largest = Enum.max(log_weights)
    mean = Enum.sum(Enum.map(log_weights, &:math.exp(&1 - largest))) / length(log_weights)
    largest + :math.log(mean)
  end

  @doc """
  Counts for the latency-exceedance version test: `{x_new, n_new, x_old,
  n_old}` where `x` is a version's requests in buckets strictly above
  `threshold` (the old version's p95 bucket, fixed before the window) and `n`
  its requests. Under equal latency distributions both versions exceed the
  fixed threshold with the same probability, so `window_log_lrs/4` applies
  unchanged.
  """
  @spec exceedance_counts(map(), map(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def exceedance_counts(new_histogram, old_histogram, threshold) do
    {x_new, n_new} = Statistics.exceedance(new_histogram, threshold)
    {x_old, n_old} = Statistics.exceedance(old_histogram, threshold)
    {x_new, n_new, x_old, n_old}
  end

  @doc "The mixture e-value of a single window."
  @spec window_e(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: float()
  def window_e(x_new, n_new, x_old, n_old), do: e_value(window_log_lrs(x_new, n_new, x_old, n_old))

  @doc "The log mixture e-value of a single window, including extreme evidence in either direction."
  @spec window_log_e(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: float()
  def window_log_e(x_new, n_new, x_old, n_old), do: log_e_value(window_log_lrs(x_new, n_new, x_old, n_old))
end
