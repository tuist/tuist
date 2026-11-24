defmodule Symptoms.Evidence.Burst do
  @moduledoc """
  Offline/shadow candidate detector for isolated service-wide error bursts.
  It does not feed the sustained detector, open symptoms or authorize pages.

  Evaluate the total count across **all** error fingerprints of a service,
  not a fingerprint selected after observing its count. The baseline is a
  `Statistics.negative_binomial_fit/0` fitted on a separate, earlier interval
  of complete windows, including genuine zeros. Freeze it for the evaluation
  interval; never include the observation or replace missing input with zero.
  At least seven days of exposure are required. Missing input or insufficient
  history is unknown, not healthy evidence.

  A candidate's negative-binomial Chernoff upper-tail bound is below the
  nominal per-service daily crossing budget (default 0.001), divided by the
  number of windows per day. Computation stays in log space. The Poisson
  limit is used at zero overdispersion; a zero fitted mean uses the same
  one-event rate floor as `Statistics.negative_binomial_residual/2`.

  **Model-conditional only:** this is a tail bound under the supplied model,
  not a calibrated production p-value or confidence. Fitted parameters,
  non-stationarity and model misspecification invalidate any unconditional
  false-positive guarantee. Held-out independent incident/quiet labels must
  validate recall and false crossings before live integration. The candidate
  flag is deliberately not an e-value and bypasses neither calibration nor
  the sustained detector's first-hour gate.
  """

  alias Symptoms.Evidence.Statistics

  @day_seconds 86_400
  @minimum_history_seconds 7 * @day_seconds
  @daily_budget 0.001

  @type result :: %{
          candidate: boolean(),
          observed: non_neg_integer(),
          expected: float(),
          log_tail_bound: float(),
          log_cutoff: float()
        }

  @doc """
  Scores one count against a frozen earlier fit. Options: `:window_seconds`
  (300) and `:crossings_per_service_day` (0.001). The latter is a nominal
  model-conditional budget, not a measured production false-positive rate.
  """
  @spec evaluate(non_neg_integer() | nil, Statistics.negative_binomial_fit() | nil, keyword()) ::
          {:ok, result()} | {:unknown, atom()}
  def evaluate(count, baseline, opts \\ [])
  def evaluate(nil, _baseline, _opts), do: {:unknown, :missing_observation}
  def evaluate(_count, nil, _opts), do: {:unknown, :missing_baseline}

  def evaluate(count, %{mean: mean, alpha: alpha, n: n}, opts) do
    seconds = Keyword.get(opts, :window_seconds, 300)

    if n * seconds < @minimum_history_seconds do
      {:unknown, :insufficient_history}
    else
      budget = Keyword.get(opts, :crossings_per_service_day, @daily_budget)
      cutoff = :math.log(budget) + :math.log(seconds / @day_seconds)
      bound = log_tail_bound(count, max(mean, 1 / (n + 1)), alpha)

      {:ok,
       %{
         candidate: bound <= cutoff,
         observed: count,
         expected: mean * 1.0,
         log_tail_bound: bound,
         log_cutoff: cutoff
       }}
    end
  end

  defp log_tail_bound(count, mean, _alpha) when count <= mean, do: 0.0
  defp log_tail_bound(count, mean, alpha) when alpha == 0, do: count - mean + count * :math.log(mean / count)

  defp log_tail_bound(count, mean, alpha) do
    log_ratio = log1p(alpha * (count - mean) / (1 + alpha * mean))
    delta = (mean - count) / (count * (1 + alpha * mean))

    # For large dispersion the second ratio is near one: adding two large
    # logs would erase its distance from one. Near zero, use the log form
    # instead so rounding delta to -1 cannot turn a finite bound infinite.
    log_product = if delta < -0.5, do: :math.log(mean / count) + log_ratio, else: log1p(delta)
    min(0.0, log_ratio / alpha + count * log_product)
  end

  # OTP's :math has no log1p. The correction retains small increments that
  # rounding 1+x would otherwise erase, including the Poisson limit.
  defp log1p(x) do
    sum = 1 + x
    if sum == 1, do: x, else: :math.log(sum) * (x / (sum - 1))
  end
end
