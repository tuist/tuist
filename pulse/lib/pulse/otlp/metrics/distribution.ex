defmodule Pulse.OTLP.Metrics.Distribution do
  @moduledoc false

  alias Pulse.OTLP.Value
  alias Pulse.PromQL.Number

  @uint64 18_446_744_073_709_551_615
  # Exponential projection grid: ~9% bucket width, at most 160 buckets a point.
  @target_scale 3
  @max_buckets 160
  @max_raw_buckets 65_536

  # Projections are derived samples, never a replacement for the source point.
  # In particular absent optional fields stay absent in the retained envelope.
  def normalize(kind, data, point, maximum, stale? \\ false)

  # Delta (1) and cumulative (2) distributions project identically: buckets
  # accumulate within a point, never across points. Unspecified (0) rejects.
  def normalize("histogram", data, point, maximum, stale?) do
    with {:ok, temporality} when temporality in [1, 2] <-
           Value.integer(Value.field(data, "aggregationTemporality", 0), 0, 2),
         {:ok, count} <- Value.integer(Value.field(point, "count", 0), 0, @uint64),
         :ok <- raw_histogram_size(point, maximum),
         {:ok, buckets} <- counts(Value.field(point, "bucketCounts", [])),
         {:ok, bounds, values} <- bounds(Value.field(point, "explicitBounds", [])),
         true <- (buckets == [] and bounds == []) or length(buckets) == length(bounds) + 1,
         true <- stale? or buckets == [] or Enum.sum(buckets) == count,
         {:ok, optional} <- optional(point, ~w(sum min max)),
         true <- stale? or count != 0 or not Map.has_key?(optional, "sum") or zero?(optional["sum"]),
         :ok <- expansion(histogram_size(buckets, values, optional), maximum) do
      source =
        Map.merge(optional, %{
          "aggregationTemporality" => temporality,
          "count" => Integer.to_string(count),
          "bucketCounts" => Enum.map(buckets, &Integer.to_string/1),
          "explicitBounds" => bounds
        })

      with {:ok, projected} <- histogram_buckets(buckets, values, count, stale?) do
        {:ok, source, projected ++ scalar_components(count, optional)}
      end
    else
      {:error, _} = error -> error
      _ -> :error
    end
  end

  # Exponential histograms project to classic cumulative `le` buckets so stock
  # `histogram_quantile` works. Points finer than @target_scale are downscaled
  # to it, and further only when they would exceed @max_buckets, so series
  # share one boundary grid and `sum by (le)` stays meaningful. Bucket
  # boundaries are base^index with base = 2^(2^-scale); the zero bucket's
  # upper bound is the zero threshold. The source envelope keeps the
  # original scale and buckets.
  def normalize("exponentialHistogram", data, point, maximum, stale?) do
    with {:ok, temporality} when temporality in [1, 2] <-
           Value.integer(Value.field(data, "aggregationTemporality", 0), 0, 2),
         {:ok, count} <- Value.integer(Value.field(point, "count", 0), 0, @uint64),
         {:ok, scale} <- Value.integer(Value.field(point, "scale", 0), -10, 20),
         {:ok, zero} <- Value.integer(Value.field(point, "zeroCount", 0), 0, @uint64),
         {:ok, threshold, projected_threshold} <- double(Value.field(point, "zeroThreshold", 0)),
         true <- is_number(projected_threshold) and projected_threshold >= 0,
         {:ok, positive} <- exponential_buckets(Value.field(point, "positive", nil)),
         {:ok, negative} <- exponential_buckets(Value.field(point, "negative", nil)),
         true <- stale? or zero + bucket_total(positive) + bucket_total(negative) == count,
         {:ok, optional} <- optional(point, ~w(sum min max)),
         true <- stale? or count != 0 or not Map.has_key?(optional, "sum") or zero?(optional["sum"]),
         true <- stale? or outside_zero?(scale, positive, projected_threshold),
         true <- stale? or outside_zero?(scale, negative, projected_threshold),
         {:ok, grid, positive, negative} <- downscale(scale, positive, negative),
         :ok <- expansion(map_size(positive) + map_size(negative) + 2 + map_size(Map.take(optional, ["sum"])), maximum) do
      source =
        optional
        |> Map.merge(%{
          "aggregationTemporality" => temporality,
          "count" => Integer.to_string(count),
          "scale" => scale,
          "zeroCount" => Integer.to_string(zero),
          "zeroThreshold" => threshold,
          "positive" => source_buckets(Value.field(point, "positive", nil)),
          "negative" => source_buckets(Value.field(point, "negative", nil))
        })
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      buckets = exponential_cumulative(grid, negative, zero, projected_threshold, positive, count)
      {:ok, source, buckets ++ scalar_components(count, optional)}
    else
      {:error, _} = error -> error
      _ -> :error
    end
  end

  def normalize("summary", _data, point, maximum, stale?) do
    with {:ok, count} <- Value.integer(Value.field(point, "count", 0), 0, @uint64),
         {:ok, sum, projected_sum} <- double(Value.field(point, "sum", 0)),
         true <- stale? or count != 0 or zero?(sum),
         quantiles when is_list(quantiles) <- Value.field(point, "quantileValues", []),
         :ok <- expansion(length(quantiles) + 2, maximum),
         {:ok, quantiles, projections} <- quantiles(quantiles, stale?) do
      {:ok, %{"count" => Integer.to_string(count), "sum" => sum, "quantileValues" => quantiles},
       projections ++ [{"_count", nil, count / 1, "count"}, {"_sum", nil, projected_sum, "sum"}]}
    else
      {:error, _} = error -> error
      _ -> :error
    end
  end

  # Exponential bucket maps (index => count). Empty buckets are dropped: they
  # add no cumulative information. Raw arrays are bounded before parsing.
  defp exponential_buckets(nil), do: {:ok, %{}}

  defp exponential_buckets(%{} = buckets) do
    counts = Value.field(buckets, "bucketCounts", [])

    with true <- is_list(counts),
         :ok <- expansion(length(counts), @max_raw_buckets),
         {:ok, offset} <- Value.integer(Value.field(buckets, "offset", 0), -2_147_483_648, 2_147_483_647),
         {:ok, counts} <- counts(counts) do
      {:ok,
       counts
       |> Enum.with_index(offset)
       |> Enum.reject(fn {count, _index} -> count == 0 end)
       |> Map.new(fn {count, index} -> {index, count} end)}
    else
      {:error, _} = error -> error
      _ -> :error
    end
  end

  defp exponential_buckets(_), do: :error

  defp bucket_total(buckets), do: buckets |> Map.values() |> Enum.sum()

  defp source_buckets(nil), do: nil

  defp source_buckets(buckets) do
    {:ok, offset} = Value.integer(Value.field(buckets, "offset", 0), -2_147_483_648, 2_147_483_647)
    {:ok, counts} = counts(Value.field(buckets, "bucketCounts", []))
    %{"offset" => offset, "bucketCounts" => Enum.map(counts, &Integer.to_string/1)}
  end

  # Merging 2^k adjacent buckets lowers the scale by k: index >> k.
  defp downscale(scale, positive, negative) do
    target = min(scale, @target_scale)
    shrink(target, shift_buckets(positive, scale - target), shift_buckets(negative, scale - target))
  end

  defp shrink(scale, positive, negative) do
    cond do
      map_size(positive) + map_size(negative) <= @max_buckets -> {:ok, scale, positive, negative}
      scale > -10 -> shrink(scale - 1, shift_buckets(positive, 1), shift_buckets(negative, 1))
      true -> {:error, :too_many_records}
    end
  end

  # A populated source bucket wholly inside the closed zero region contradicts
  # that region. Partial overlap is valid: its observations are outside zero.
  # Threshold zero needs no rounded-bound comparison in the subnormal tail.
  defp outside_zero?(_scale, _buckets, threshold) when threshold == 0, do: true

  defp outside_zero?(scale, buckets, threshold) do
    Enum.all?(buckets, fn {index, _count} ->
      upper = bound(scale, index + 1)
      upper == :infinity or upper > threshold
    end)
  end

  defp shift_buckets(buckets, 0), do: buckets

  defp shift_buckets(buckets, shift) do
    Enum.reduce(buckets, %{}, fn {index, count}, acc ->
      Map.update(acc, Bitwise.bsr(index, shift), count, &(&1 + count))
    end)
  end

  # Ascending upper bounds: negative buckets, zero, positive buckets, then +Inf.
  # Equal rounded bounds coalesce at THAT boundary, not the next one. Keeping
  # the earlier cumulative value would lose mass at subnormal/zero collisions.
  defp exponential_cumulative(scale, negative, zero, threshold, positive, count) do
    negatives =
      for index <- negative |> Map.keys() |> Enum.sort(:desc),
          do: {negative_upper(bound(scale, index), threshold), negative[index]}

    positives =
      for index <- positive |> Map.keys() |> Enum.sort(),
          do: {positive_upper(bound(scale, index + 1), threshold), positive[index]}

    {rows, _, _} =
      Enum.reduce(negatives ++ [{threshold / 1, zero}] ++ positives, {[], 0, nil}, fn {upper, n},
                                                                                      {rows, total, previous} ->
        total = total + n

        # Normalize projected signed zero only; source float bits stay intact.
        upper = if upper == 0.0, do: 0.0, else: upper

        cond do
          upper == :infinity ->
            {rows, total, previous}

          upper == previous ->
            [{suffix, label, _old, component} | rest] = rows
            {[{suffix, label, total / 1, component} | rest], total, previous}

          true ->
            {[{"_bucket", {"le", label(upper)}, total / 1, "bucket"} | rows], total, upper}
        end
      end)

    Enum.reverse([{"_bucket", {"le", "+Inf"}, count / 1, "bucket"} | rows])
  end

  defp bound(scale, index) do
    exponent = index * :math.pow(2, -scale)

    cond do
      exponent >= 1024 -> :infinity
      exponent <= -1075 -> 0.0
      true -> :math.pow(2.0, exponent)
    end
  end

  # Clamping only affects ignored values of stale contradictory source points;
  # ordinary points wholly inside zero have already rejected above.
  defp positive_upper(:infinity, _threshold), do: :infinity
  defp positive_upper(value, threshold), do: max(value, threshold)

  defp negative_upper(:infinity, _threshold), do: :negative_infinity
  defp negative_upper(value, threshold), do: -max(value, threshold)

  # Check raw cardinality before parsing duplicate arrays or constructing rows.
  defp raw_histogram_size(point, maximum) do
    counts = Value.field(point, "bucketCounts", [])
    bounds = Value.field(point, "explicitBounds", [])
    optional = if Map.get(point, "sum") == nil, do: %{}, else: %{"sum" => true}

    with true <- is_list(counts) and is_list(bounds),
         true <- (counts == [] and bounds == []) or length(counts) == length(bounds) + 1 do
      duplicate = if List.last(bounds) == "Infinity" and counts != [], do: 1, else: 0
      expansion(max(1, length(counts) - duplicate) + 1 + map_size(optional), maximum)
    else
      _ -> :error
    end
  end

  defp expansion(size, maximum), do: if(size <= maximum, do: :ok, else: {:error, :too_many_records})

  defp histogram_size(buckets, bounds, optional) do
    duplicate = if List.last(bounds) == :infinity and buckets != [], do: 1, else: 0
    max(1, length(buckets) - duplicate) + 1 + if(Map.has_key?(optional, "sum"), do: 1, else: 0)
  end

  defp scalar_components(count, optional) do
    sum = if Map.has_key?(optional, "sum"), do: [{"_sum", nil, ieee(optional["sum"]), "sum"}], else: []
    [{"_count", nil, count / 1, "count"} | sum]
  end

  # Even without finite buckets, the total count proves the universal +Inf
  # bucket. No finite distribution is inferred from omitted source arrays.
  defp histogram_buckets([], [], count, _stale?), do: {:ok, [{"_bucket", {"le", "+Inf"}, count / 1, "bucket"}]}

  defp histogram_buckets(buckets, bounds, _count, stale?) do
    values = Enum.zip(bounds ++ [:infinity], Enum.scan(buckets, 0, &+/2))

    Enum.reduce_while(values, {:ok, [], nil}, fn {bound, count}, {:ok, acc, previous} ->
      label = label(bound)

      case previous do
        {^label, ^count} -> {:cont, {:ok, acc, previous}}
        {^label, _} when stale? -> {:cont, {:ok, acc, previous}}
        {^label, _} -> {:halt, :error}
        _ -> {:cont, {:ok, [{"_bucket", {"le", label}, count / 1, "bucket"} | acc], {label, count}}}
      end
    end)
    |> case do
      {:ok, rows, _} -> {:ok, Enum.reverse(rows)}
      other -> other
    end
  end

  defp quantiles(values, stale?) do
    Enum.reduce_while(values, {:ok, [], [], nil}, fn value, {:ok, source, rows, previous} ->
      with %{} <- value,
           {:ok, q, projected_q} <- double(Value.field(value, "quantile", 0)),
           true <- is_number(projected_q) and projected_q >= 0 and projected_q <= 1,
           true <- is_nil(previous) or projected_q > previous,
           {:ok, v, projected_v} <- double(Value.field(value, "value", 0)),
           true <- stale? or projected_v in [:nan, :infinity] or (is_number(projected_v) and projected_v >= 0) do
        {:cont,
         {:ok, [%{"quantile" => q, "value" => v} | source],
          [{"", {"quantile", label(projected_q)}, projected_v, "quantile"} | rows], projected_q}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, source, rows, _} -> {:ok, Enum.reverse(source), Enum.reverse(rows)}
      other -> other
    end
  end

  defp counts(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case Value.integer(value, 0, @uint64) do
        {:ok, count} -> {:cont, {:ok, [count | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end
  end

  defp counts(_), do: :error

  defp bounds(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, [], [], nil}, fn value, {:ok, source, projected, previous} ->
      with {:ok, typed, number} <- double(value),
           true <- number != :nan,
           true <- is_nil(previous) or Number.compare(">", number, previous) do
        {:cont, {:ok, [typed | source], [number | projected], number}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, source, projected, _} -> {:ok, Enum.reverse(source), Enum.reverse(projected)}
      other -> other
    end
  end

  defp bounds(_), do: :error

  defp optional(point, names) do
    Enum.reduce_while(names, {:ok, %{}}, &optional_field(point[&1], &1, &2))
  end

  defp optional_field(nil, _name, acc), do: {:cont, acc}

  defp optional_field(value, name, {:ok, acc}) do
    case double(value) do
      {:ok, typed, _} -> {:cont, {:ok, Map.put(acc, name, typed)}}
      _ -> {:halt, :error}
    end
  end

  defp double(value) do
    with {:ok, _, %{"doubleValue" => typed}} <- Value.decode(%{"doubleValue" => value}),
         do: {:ok, typed, ieee(typed)}
  end

  defp ieee("NaN"), do: :nan
  defp ieee("Infinity"), do: :infinity
  defp ieee("-Infinity"), do: :negative_infinity
  defp ieee(value), do: value
  defp zero?(value), do: is_number(value) and value == 0

  defp label(:infinity), do: "+Inf"
  defp label(:negative_infinity), do: "-Inf"
  defp label(value) when is_integer(value), do: Integer.to_string(value)

  defp label(value) do
    # Fixed-decimal shortest-roundtrip spelling, as used for Prometheus bounds.
    [mantissa | exponent] = String.split(Float.to_string(value), "e")

    {sign, mantissa} =
      if String.starts_with?(mantissa, "-"), do: {"-", String.trim_leading(mantissa, "-")}, else: {"", mantissa}

    [whole, fraction] = String.split(mantissa, ".")
    digits = whole <> fraction
    position = byte_size(whole) + if(exponent == [], do: 0, else: String.to_integer(hd(exponent)))

    fixed =
      cond do
        position <= 0 -> "0." <> String.duplicate("0", -position) <> digits
        position >= byte_size(digits) -> digits <> String.duplicate("0", position - byte_size(digits))
        true -> binary_part(digits, 0, position) <> "." <> binary_part(digits, position, byte_size(digits) - position)
      end

    fixed =
      if String.contains?(fixed, "."), do: fixed |> String.trim_trailing("0") |> String.trim_trailing("."), else: fixed

    sign <> fixed
  end
end
