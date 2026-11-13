defmodule Pulse.PromQL.RangeMath do
  @moduledoc false
  alias Pulse.PromQL.Number, as: N
  alias Pulse.PromQL.Time

  # Float algorithms from Prometheus v3.5.0 promql/functions.go, using the same
  # Neumaier compensated sums and constant-series regression special case.
  def variance(samples) do
    {count, _mean, _cm, aux, ca} =
      Enum.reduce(samples, {0, 0.0, 0.0, 0.0, 0.0}, fn sample, {count, mean, cm, aux, ca} ->
        count = count + 1
        delta = N.binary("-", sample.value, N.add(mean, cm))
        {mean, cm} = N.compensated_add(N.divide(delta, count), mean, cm)
        inc = N.multiply(delta, N.binary("-", sample.value, N.add(mean, cm)))
        {aux, ca} = N.compensated_add(inc, aux, ca)
        {count, mean, cm, aux, ca}
      end)

    N.divide(N.add(aux, ca), count)
  end

  def deviation(samples) do
    case variance(samples) do
      value when is_number(value) and value >= 0 -> :math.sqrt(value)
      :infinity -> :infinity
      _ -> :nan
    end
  end

  def quantile(:nan, _samples), do: :nan
  def quantile(q, _samples) when q == :negative_infinity or (is_number(q) and q < 0), do: :negative_infinity
  def quantile(q, _samples) when q == :infinity or (is_number(q) and q > 1), do: :infinity

  def quantile(q, samples) do
    values = samples |> Enum.map(& &1.value) |> Enum.sort(fn a, b -> N.nan?(a) or N.compare("<=", a, b) end)
    rank = q * (length(values) - 1)
    lower = trunc(rank)
    weight = rank - lower

    # An exact rank reads only that observation: zero times an adjacent
    # infinity or NaN would otherwise contaminate a finite result or -0.
    if weight == 0,
      do: Enum.at(values, lower),
      else: N.add(N.multiply(Enum.at(values, lower), 1 - weight), N.multiply(Enum.at(values, lower + 1), weight))
  end

  def smooth([first, second | _] = samples, sf, tf) do
    initial_trend = N.binary("-", second.value, first.value)

    {_, level, _} =
      Enum.reduce(tl(samples), {nil, first.value, initial_trend}, fn sample, {previous, level, trend} ->
        weighted = N.multiply(sf, sample.value)

        trend =
          if is_nil(previous),
            do: trend,
            else: N.add(N.multiply(tf, N.binary("-", level, previous)), N.multiply(N.binary("-", 1, tf), trend))

        next = N.add(weighted, N.multiply(N.binary("-", 1, sf), N.add(level, trend)))
        {level, next, trend}
      end)

    level
  end

  def smooth(_, _, _), do: nil

  def mad(samples) do
    values = Enum.map(samples, & &1.value)

    if Enum.any?(values, &N.nan?/1) do
      :nan
    else
      center = median(values)
      values |> Enum.map(&absolute_difference(&1, center)) |> median()
    end
  end

  defp median(values) do
    sorted = Enum.sort(values, fn a, b -> N.nan?(a) or N.compare("<=", a, b) end)
    count = length(sorted)
    upper = div(count, 2)

    if rem(count, 2) == 1,
      do: Enum.at(sorted, upper),
      else: N.add(N.multiply(Enum.at(sorted, upper - 1), 0.5), N.multiply(Enum.at(sorted, upper), 0.5))
  end

  defp absolute_difference(value, center) do
    case N.binary("-", value, center) do
      value when is_number(value) -> abs(value)
      :negative_infinity -> :infinity
      value -> value
    end
  end

  def predict(samples, origin, horizon) when length(samples) >= 2 do
    {slope, intercept} = regression(samples, origin)
    N.add(N.multiply(slope, horizon), intercept)
  end

  def predict(_, _, _), do: nil

  def deriv([first, _ | _] = samples) do
    {slope, _} = regression(samples, first.timestamp_ns)
    slope
  end

  def deriv(_), do: nil

  defp regression(samples, origin) do
    values = Enum.map(samples, & &1.value)
    first = hd(values)

    if Enum.all?(values, &N.compare("==", &1, first)) do
      if is_number(first), do: {0.0, first}, else: {:nan, :nan}
    else
      {sx, sy, sxy, sx2} = sums(samples, origin)
      n = length(samples)
      covariance = N.binary("-", sxy, N.divide(N.multiply(sx, sy), n))
      variance = N.binary("-", sx2, N.divide(N.multiply(sx, sx), n))
      slope = N.divide(covariance, variance)
      intercept = N.binary("-", N.divide(sy, n), N.divide(N.multiply(slope, sx), n))
      {slope, intercept}
    end
  end

  defp sums(samples, origin) do
    initial = {{0.0, 0.0}, {0.0, 0.0}, {0.0, 0.0}, {0.0, 0.0}}

    {sx, sy, sxy, sx2} =
      Enum.reduce(samples, initial, fn sample, {sx, sy, sxy, sx2} ->
        x = Time.seconds(sample.timestamp_ns - origin)
        y = sample.value
        {inc(x, sx), inc(y, sy), inc(N.multiply(x, y), sxy), inc(N.multiply(x, x), sx2)}
      end)

    {total(sx), total(sy), total(sxy), total(sx2)}
  end

  defp inc(value, {sum, correction}), do: N.compensated_add(value, sum, correction)
  defp total({sum, correction}), do: N.add(sum, correction)
end
