defmodule Pulse.PromQL.Histogram do
  @moduledoc false
  alias Pulse.GoUnicode
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.NativeHistogram
  alias Pulse.PromQL.Number
  alias Pulse.Record.NativeHistogram, as: Histogram

  def quantile(q, vector) do
    quantile_groups(q, Enum.reduce(vector, %{}, &collect/2))
  end

  def quantiles(vector, destination, qs) do
    groups = Enum.reduce(vector, %{}, &collect/2)

    # Bound the entire potential fan-out before constructing output labels.
    Evaluator.charge(:materialized, map_size(groups) * length(qs))

    Enum.flat_map(qs, fn q ->
      text = Number.format(q, :open_metrics)

      for {labels, value} <- quantile_groups(q, groups) do
        Evaluator.charge(:work, byte_size(destination) + byte_size(text) + 1)
        labels = labels |> Map.put(destination, text) |> Map.delete("__name__")
        {labels, value}
      end
    end)
  end

  defp quantile_groups(q, groups) do
    Evaluator.quantile_warning(q)

    evaluate_histograms(groups, &NativeHistogram.quantile_with_info(q, &1), &bucket_quantile(q, &1))
  end

  def fraction(lower, upper, vector) do
    groups = Enum.reduce(vector, %{}, &collect/2)

    evaluate_histograms(
      groups,
      &NativeHistogram.fraction_with_info(lower, upper, &1),
      &bucket_fraction(lower, upper, &1)
    )
  end

  defp evaluate_histograms(groups, native, classic) do
    Enum.flat_map(groups, fn
      {labels, {histogram, []}} ->
        Evaluator.charge(
          :work,
          1 + length(histogram.positive_buckets) + length(histogram.negative_buckets) + length(histogram.custom_values)
        )

        {value, infos} = native.(histogram)
        Enum.each(infos, &native_info(&1, labels))
        [{Map.delete(labels, "__name__"), value}]

      {labels, {nil, buckets}} ->
        Evaluator.charge(:work, length(buckets))
        [{Map.delete(labels, "__name__"), classic.(Enum.reverse(buckets))}]

      {labels, {_histogram, _buckets}} ->
        Evaluator.warning(
          "PromQL warning: vector contains a mix of classic and native histograms" <> metric_name(labels)
        )

        []
    end)
  end

  defp native_info(kind, labels) do
    message =
      case kind do
        :nan_result -> "histogram_quantile has NaN observations, result is NaN"
        :nan_skew -> "histogram_quantile has NaN observations, result is skewed higher"
        :nan_observations -> "histogram_fraction has NaN observations, which are excluded from all fractions"
      end

    Evaluator.info("PromQL info: input to " <> message <> metric_name(labels))
  end

  @doc """
  Parses each series' `le` bound once, so the per-step functions above do
  not parse and regroup every series again at every step. Series keep their
  samples; their labels become `{:bucket, labels, group, bound}`.
  """
  def parse_buckets(series) do
    for {labels, samples} <- series do
      bound =
        case FloatParser.parse(Map.get(labels, "le", "")) do
          {:ok, bound} when bound != :nan -> bound
          _ -> :invalid
        end

      {{:bucket, labels, Map.delete(labels, "le"), bound}, samples}
    end
  end

  # Keep metric names and native le labels until collision detection. Only
  # successfully parsed classic buckets can conflict with a native histogram.
  defp collect({{:bucket, labels, _, _}, %Histogram{} = histogram}, groups), do: collect({labels, histogram}, groups)

  defp collect({{:bucket, labels, _, :invalid}, _count}, groups) do
    Evaluator.warning(
      "PromQL warning: bucket label \"le\" is missing or has a malformed value of " <>
        GoUnicode.quote(Map.get(labels, "le", "")) <> metric_name(labels)
    )

    groups
  end

  defp collect({{:bucket, _labels, group, bound}, count}, groups) do
    Map.update(groups, group, {nil, [{bound, count}]}, fn {histogram, buckets} ->
      {histogram, [{bound, count} | buckets]}
    end)
  end

  defp collect({labels, %Histogram{} = histogram}, groups) do
    Map.update(groups, labels, {histogram, []}, fn {_, buckets} -> {histogram, buckets} end)
  end

  defp metric_name(labels) do
    case Map.get(labels, "__name__", "") do
      "" -> ""
      name -> " for metric name " <> GoUnicode.quote(name)
    end
  end

  defp bucket_quantile(:nan, _), do: :nan

  defp bucket_quantile(q, values) do
    cond do
      Number.compare("<", q, 0) ->
        :negative_infinity

      Number.compare(">", q, 1) ->
        :infinity

      true ->
        values
        |> Enum.sort(fn {a, _}, {b, _} -> not Number.compare(">", a, b) end)
        |> coalesce()
        |> quantile_result(q)
    end
  end

  defp bucket_fraction(lower, upper, values) do
    buckets = values |> Enum.sort(fn {a, _}, {b, _} -> not Number.compare(">", a, b) end) |> coalesce()
    {last, count} = List.last(buckets)

    cond do
      last != :infinity or Number.compare("==", count, 0) or lower == :nan or upper == :nan -> :nan
      Number.compare(">=", lower, upper) -> 0.0
      true -> fraction_result(lower, upper, buckets, count)
    end
  end

  defp fraction_result(lower, upper, buckets, count) do
    first = if Number.compare("<=", elem(hd(buckets), 0), 0), do: :negative_infinity, else: 0.0
    lower_rank = fraction_rank(lower, buckets, first, 0.0)
    upper_rank = fraction_rank(upper, buckets, first, 0.0)
    lower_rank = if Number.compare(">", lower_rank, count), do: count, else: lower_rank
    upper_rank = if Number.compare(">", upper_rank, count), do: count, else: upper_rank
    Number.divide(Number.binary("-", upper_rank, lower_rank), count)
  end

  defp fraction_rank(_value, [], _lower, count), do: count

  defp fraction_rank(value, [{upper, count} | rest], lower, rank) do
    cond do
      Number.compare(">=", lower, value) -> rank
      Number.compare(">", upper, value) -> interpolate_rank(value, lower, upper, rank, count)
      true -> fraction_rank(value, rest, upper, count)
    end
  end

  defp interpolate_rank(_value, :negative_infinity, _upper, _rank, count), do: count

  defp interpolate_rank(value, lower, upper, rank, count) do
    delta = Number.multiply(Number.binary("-", count, rank), Number.binary("-", value, lower))
    Number.add(rank, Number.divide(delta, Number.binary("-", upper, lower)))
  end

  defp quantile_result(buckets, q) do
    cond do
      length(buckets) < 2 -> :nan
      elem(List.last(buckets), 0) != :infinity -> :nan
      true -> monotonic_quantile(buckets, q)
    end
  end

  defp monotonic_quantile(buckets, q) do
    buckets = monotonic(buckets)
    count = elem(List.last(buckets), 1)

    if Number.compare("==", count, 0) do
      :nan
    else
      interpolate(buckets, Number.multiply(q, count))
    end
  end

  defp coalesce(buckets) do
    buckets |> Enum.reduce([], &coalesce_bucket/2) |> Enum.reverse()
  end

  defp coalesce_bucket({bound, count}, [{previous, previous_count} | rest] = acc) do
    if Number.compare("==", bound, previous),
      do: [{bound, Number.add(previous_count, count)} | rest],
      else: [{bound, count} | acc]
  end

  defp coalesce_bucket(bucket, []), do: [bucket]
  defp monotonic([]), do: []

  defp monotonic([first | rest]) do
    {result, _} =
      Enum.map_reduce(rest, elem(first, 1), fn {bound, count}, previous ->
        count = monotonic_count(count, previous)
        {{bound, count}, count}
      end)

    [first | result]
  end

  defp monotonic_count(count, previous) do
    cond do
      Number.compare("==", count, previous) -> count
      almost_equal?(count, previous) -> previous
      Number.compare("<", count, previous) -> force_monotonic(previous)
      true -> count
    end
  end

  defp force_monotonic(previous) do
    Evaluator.info(
      "PromQL info: input to histogram_quantile needed to be fixed for monotonicity " <>
        "(see https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile)"
    )

    previous
  end

  defp almost_equal?(a, b) when is_number(a) and is_number(b) do
    # Match upstream almost.Equal's absolute floor and capped relative scale.
    # Either intermediate can overflow even when both counts are finite.
    min_normal = 2.2250738585072014e-308
    total = Number.add(abs(a), abs(b))
    difference = Number.binary("-", max(a, b), min(a, b))

    if a == 0 or b == 0 or Number.compare("<", total, min_normal) do
      Number.compare("<", difference, 1.0e-12 * min_normal)
    else
      scale = Number.min(total, 1.797_693_134_862_315_7e308)
      Number.compare("<", Number.divide(difference, scale), 1.0e-12)
    end
  end

  defp almost_equal?(_, _), do: false

  defp interpolate(buckets, rank) do
    # Prometheus uses sort.Search even for NaN counts; its predicate can be
    # non-monotone in that case, so a linear first-match scan is not equivalent.
    tuple = List.to_tuple(buckets)
    index = search(tuple, rank, 0, tuple_size(tuple) - 1)

    cond do
      index == tuple_size(tuple) - 1 -> elem(elem(tuple, index - 1), 0)
      index == 0 and Number.compare("<=", elem(elem(tuple, 0), 0), 0) -> elem(elem(tuple, 0), 0)
      true -> interpolate_bucket(tuple, index, rank)
    end
  end

  defp search(_buckets, _rank, low, high) when low >= high, do: low

  defp search(buckets, rank, low, high) do
    middle = div(low + high, 2)

    if Number.compare(">=", elem(elem(buckets, middle), 1), rank),
      do: search(buckets, rank, low, middle),
      else: search(buckets, rank, middle + 1, high)
  end

  defp interpolate_bucket(buckets, index, rank) do
    {upper, count} = elem(buckets, index)
    {lower, previous} = if index == 0, do: {0.0, 0.0}, else: elem(buckets, index - 1)
    count = Number.binary("-", count, previous)
    rank = Number.binary("-", rank, previous)
    Number.add(lower, Number.multiply(Number.binary("-", upper, lower), Number.divide(rank, count)))
  end
end
