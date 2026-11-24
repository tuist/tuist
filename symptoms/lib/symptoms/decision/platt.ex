defmodule Symptoms.Decision.Platt do
  @moduledoc """
  Platt scaling: `P(degraded) = 1 / (1 + exp(-(a + b · score)))`
  (`symptoms/README.md` "Combining", step 4, and the cadence table).

  - `prior/2`: before labels exist, the score at the CUSUM threshold `h` maps
    to P = 0.5 (`a = -b · h`).
  - `fit/2`: intercept and slope fitted on all labels by Newton's method on
    the logistic log-likelihood with a small L2 prior pulling towards the
    prior parameters.
  - `bounded_refit/3`: the event-triggered refit (after a missed incident or
    a page labelled fine) refits the intercept only, slope fixed, and moves
    it by at most 0.5 logit. The replay gate that decides whether to apply it
    lives outside this module.

  Samples are `{score, label}` or `{score, label, weight}` with a `true`/`1`
  label for degraded. The weight carries the inverse of the recorded delay
  probability for delayed items.
  """

  @default_lambda 1.0e-2
  @max_intercept_shift 0.5
  @max_iterations 100
  @tolerance 1.0e-10

  @type params :: %{a: float(), b: float()}
  @type sample ::
          {number(), boolean() | 0 | 1} | {number(), boolean() | 0 | 1, number()}

  @doc "P(degraded) for a score."
  @spec probability(params(), number()) :: float()
  def probability(%{a: a, b: b}, score), do: sigmoid(a + b * score)

  @doc """
  The prior mapping: P(h) = 0.5 with the given slope (default 1 per nat), so
  `%{a: -slope · h, b: slope}`.
  """
  @spec prior(number(), number()) :: params()
  def prior(h, slope \\ 1.0), do: %{a: -slope * h * 1.0, b: slope * 1.0}

  @doc """
  Fits intercept and slope. Options: `:prior` (default `%{a: 0.0, b: 0.0}`),
  the centre of the L2 penalty and Newton's starting point, and `:lambda`
  (default #{@default_lambda}), the penalty `λ/2 · |θ - θ₀|²`.
  """
  @spec fit([sample()], keyword()) :: params()
  def fit(samples, opts \\ []) do
    prior = Keyword.get(opts, :prior, %{a: 0.0, b: 0.0})
    lambda = Keyword.get(opts, :lambda, @default_lambda)
    samples = Enum.map(samples, &normalize/1)

    newton(samples, {prior.a * 1.0, prior.b * 1.0}, {prior.a, prior.b}, lambda, @max_iterations)
  end

  defp newton(_samples, {a, b}, _prior, _lambda, 0), do: %{a: a, b: b}

  defp newton(samples, {a, b}, {a0, b0} = prior, lambda, iterations) do
    {ga, gb, haa, hab, hbb} =
      Enum.reduce(samples, {lambda * (a - a0), lambda * (b - b0), lambda, 0.0, lambda}, fn {s, y, w},
                                                                                           {ga, gb, haa, hab, hbb} ->
        p = sigmoid(a + b * s)
        r = w * (p - y)
        v = w * p * (1 - p)
        {ga + r, gb + r * s, haa + v, hab + v * s, hbb + v * s * s}
      end)

    det = haa * hbb - hab * hab
    da = (hbb * ga - hab * gb) / det
    db = (haa * gb - hab * ga) / det
    {next_a, next_b} = line_search(samples, {a, b}, {da, db}, prior, lambda)

    if abs(next_a - a) + abs(next_b - b) < @tolerance,
      do: %{a: next_a, b: next_b},
      else: newton(samples, {next_a, next_b}, prior, lambda, iterations - 1)
  end

  # Halves the Newton step until the penalized loss does not increase. With
  # (nearly) separable labels a full step overshoots and oscillates.
  defp line_search(samples, {a, b}, {da, db}, prior, lambda) do
    current = loss(samples, {a, b}, prior, lambda)

    0..40
    |> Enum.reduce_while(1.0, fn _, t ->
      candidate = {a - t * da, b - t * db}
      if loss(samples, candidate, prior, lambda) <= current, do: {:halt, candidate}, else: {:cont, t / 2}
    end)
    |> case do
      {_, _} = candidate -> candidate
      _ -> {a, b}
    end
  end

  defp loss(samples, {a, b}, {a0, b0}, lambda) do
    samples
    |> Enum.map(fn {s, y, w} ->
      z = a + b * s
      w * (softplus(z) - y * z)
    end)
    |> Enum.sum()
    |> Kernel.+(lambda / 2 * ((a - a0) ** 2 + (b - b0) ** 2))
  end

  defp softplus(z) when z > 0, do: z + :math.log(1 + :math.exp(-z))
  defp softplus(z), do: :math.log(1 + :math.exp(z))

  @doc """
  Refits the intercept with the slope fixed (same L2 prior, centred on the
  current intercept) and clamps the change to ±#{@max_intercept_shift} logit.
  Option `:lambda` as in `fit/2`.
  """
  @spec bounded_refit(params(), [sample()], keyword()) :: params()
  def bounded_refit(%{a: a, b: b} = params, samples, opts \\ []) do
    lambda = Keyword.get(opts, :lambda, @default_lambda)
    samples = Enum.map(samples, &normalize/1)
    gradient = &intercept_gradient(samples, &1, a, b, lambda)
    low = a - @max_intercept_shift
    high = a + @max_intercept_shift

    # The penalized loss is convex in the intercept, so its derivative is
    # increasing: the optimum clamped to [low, high] is an endpoint when the
    # derivative has the same sign over the interval, and is found by
    # bisection otherwise.
    fitted =
      cond do
        gradient.(high) <= 0 -> high
        gradient.(low) >= 0 -> low
        true -> bisect(gradient, low, high, 100)
      end

    %{params | a: fitted}
  end

  defp intercept_gradient(samples, a, a0, b, lambda) do
    Enum.reduce(samples, lambda * (a - a0), fn {s, y, w}, g -> g + w * (sigmoid(a + b * s) - y) end)
  end

  defp bisect(_gradient, low, high, 0), do: (low + high) / 2

  defp bisect(gradient, low, high, steps) do
    middle = (low + high) / 2

    if gradient.(middle) < 0,
      do: bisect(gradient, middle, high, steps - 1),
      else: bisect(gradient, low, middle, steps - 1)
  end

  defp normalize({score, label}), do: normalize({score, label, 1.0})
  defp normalize({score, label, weight}), do: {score * 1.0, label_value(label), weight * 1.0}

  defp label_value(label) when label in [true, 1], do: 1.0
  defp label_value(label) when label in [false, 0], do: 0.0

  defp sigmoid(x) when x >= 0, do: 1 / (1 + :math.exp(-x))

  defp sigmoid(x) do
    e = :math.exp(x)
    e / (1 + e)
  end
end
