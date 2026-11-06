defmodule Pulse.PromQL.Operations do
  @moduledoc false
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Histogram
  alias Pulse.PromQL.LabelHash
  alias Pulse.PromQL.LabelReplace
  alias Pulse.PromQL.NativeHistogram
  alias Pulse.PromQL.Number
  alias Pulse.PromQL.RangeMath
  alias Pulse.PromQL.Time
  alias Pulse.Record.NativeHistogram, as: HistogramSample

  @comparisons ["==", "!=", "<", ">", "<=", ">="]
  @histogram_property_functions %{
    "histogram_count" => :count,
    "histogram_sum" => :sum,
    "histogram_avg" => :avg,
    "histogram_stddev" => :stddev,
    "histogram_stdvar" => :stdvar
  }
  @histogram_properties Map.keys(@histogram_property_functions)
  @sets ["and", "or", "unless"]
  @trims ["</", ">/"]
  @calendar_functions ~w(year month day_of_month day_of_week day_of_year days_in_month hour minute)

  def binary(op, modifiers, left, right, left_type, right_type, steps) do
    left = by_time(left)
    right = by_time(right)
    at_steps(steps, fn ts -> binary_step(op, modifiers, at(left, ts), at(right, ts), left_type, right_type) end)
  end

  defp binary_step(op, _modifiers, lhs, rhs, :scalar, :scalar), do: [{%{}, result(op, value(lhs), value(rhs))}]

  defp binary_step(op, modifiers, lhs, rhs, :scalar, :vector),
    do: scalar_vector(op, value(lhs), rhs, true, "bool" in modifiers)

  defp binary_step(op, modifiers, lhs, rhs, :vector, :scalar),
    do: scalar_vector(op, value(rhs), lhs, false, "bool" in modifiers)

  defp binary_step(op, modifiers, lhs, rhs, _, _) when op in @sets, do: set(op, modifiers, lhs, rhs)
  defp binary_step(op, modifiers, lhs, rhs, _, _), do: vector_vector(op, modifiers, lhs, rhs)

  defp scalar_vector(op, scalar, vector, scalar_left?, boolean) do
    Enum.flat_map(vector, fn sample -> scalar_pair(op, scalar, sample, scalar_left?, boolean) end)
  end

  defp scalar_pair(op, scalar, {labels, value}, scalar_left?, boolean) do
    {a, b} = if scalar_left?, do: {scalar, value}, else: {value, scalar}

    cond do
      histogram?(a) or histogram?(b) or op in @trims -> histogram_pair(op, labels, a, b, boolean)
      filter?(op, boolean) -> filtered_sample(labels, value, Number.compare(op, a, b))
      true -> [{Map.delete(labels, "__name__"), result(op, a, b)}]
    end
  end

  # Mimir trimming keeps the histogram's name and reset hint; only a histogram
  # on the left and a float on the right can produce a result.
  defp histogram_pair(op, labels, %HistogramSample{} = h, cutoff, _boolean)
       when op in @trims and not is_struct(cutoff) do
    Evaluator.charge(:work, length(h.positive_buckets) + length(h.negative_buckets) + length(h.custom_values))
    [{labels, NativeHistogram.trim(h, cutoff, op == "</")}]
  end

  # Prometheus' `vectorElemBinop` for other histogram operands: scaling by a
  # float, adding or subtracting histograms, and comparing two for equality.
  defp histogram_pair(op, labels, a, b, boolean) do
    case {op, a, b} do
      {"*", %HistogramSample{}, b} when not is_struct(b) ->
        scaled(op, labels, a, b)

      {"*", a, %HistogramSample{}} when not is_struct(a) ->
        scaled(op, labels, b, a)

      {"/", %HistogramSample{}, b} when not is_struct(b) ->
        scaled(op, labels, a, b)

      {op, %HistogramSample{}, %HistogramSample{}} when op in ["+", "-"] ->
        combined(op, labels, a, b)

      {op, %HistogramSample{}, %HistogramSample{}} when op in ["==", "!="] ->
        equality(op, labels, a, b, boolean)

      _ ->
        left = if histogram?(a), do: "histogram", else: "float"
        right = if histogram?(b), do: "histogram", else: "float"

        Evaluator.info(
          "PromQL info: incompatible sample types encountered for binary operator \"#{op}\": #{left} #{op} #{right}"
        )

        []
    end
  end

  defp scaled(op, labels, h, factor) do
    # Division by zero drops buckets without traversing them. Multiplication
    # by zero still visits every bucket before compaction removes empty ones.
    if !(op == "/" and Number.compare("==", factor, 0.0)) do
      Evaluator.charge(:work, length(h.positive_buckets) + length(h.negative_buckets))
    end

    h = if op == "*", do: NativeHistogram.scale(h, factor), else: NativeHistogram.divide(h, factor)
    [{Map.delete(labels, "__name__"), compact(h)}]
  end

  defp combined(op, labels, a, b) do
    work =
      Enum.reduce([a, b], 0, fn h, total ->
        total + length(h.positive_buckets) + length(h.negative_buckets) + length(h.custom_values)
      end)

    Evaluator.charge(:work, work)
    result = if op == "+", do: NativeHistogram.add(a, b), else: NativeHistogram.sub(a, b)
    operation = if op == "+", do: "addition", else: "subtraction"

    case result do
      {:ok, h} ->
        if {a.counter_reset_hint, b.counter_reset_hint} in [{:yes, :no}, {:no, :yes}] do
          Evaluator.warning("PromQL warning: conflicting counter resets during histogram #{operation}")
        end

        if a.schema == HistogramSample.custom_buckets_schema() and a.custom_values != b.custom_values do
          Evaluator.info("PromQL info: mismatched custom buckets were reconciled during #{operation}")
        end

        h = if op == "-", do: %{h | counter_reset_hint: :gauge}, else: h
        [{Map.delete(labels, "__name__"), compact(h)}]

      {:error, :incompatible_schema} ->
        Evaluator.warning("PromQL warning: incompatible bucket layout encountered for binary operator #{op}")
        []
    end
  end

  defp equality(op, labels, a, b, boolean) do
    work =
      Enum.reduce([a, b], 0, fn h, total ->
        total + length(h.positive_buckets) + length(h.negative_buckets) + length(h.custom_values)
      end)

    Evaluator.charge(:work, work)
    keep = NativeHistogram.equal?(a, b) == (op == "==")

    cond do
      boolean -> [{Map.delete(labels, "__name__"), if(keep, do: 1.0, else: 0.0)}]
      keep -> [{labels, a}]
      true -> []
    end
  end

  defp compact(h), do: NativeHistogram.compact(h)
  defp histogram?(value), do: is_struct(value, HistogramSample)

  defp filtered_sample(labels, value, true), do: [{labels, value}]
  defp filtered_sample(_, _, false), do: []
  defp filter?(op, boolean), do: op in @comparisons and not boolean

  defp vector_vector(_op, _modifiers, [], _rhs), do: []
  defp vector_vector(_op, _modifiers, _lhs, []), do: []

  defp vector_vector(op, modifiers, lhs, rhs) do
    grouping = grouping(modifiers)
    right_many? = match?(["group_right" | _], grouping)
    {many, one} = if right_many?, do: {rhs, lhs}, else: {lhs, rhs}

    context = %{
      op: op,
      modifiers: modifiers,
      grouping: grouping,
      right_many?: right_many?,
      boolean: "bool" in modifiers,
      index: unique_index(one, modifiers, if(right_many?, do: :left, else: :right))
    }

    {pairs, _seen} = Enum.map_reduce(many, MapSet.new(), &matched_output(&1, &2, context))
    pairs |> List.flatten() |> unique!()
  end

  defp vector_pair({labels, value}, context) do
    key = signature(labels, context.modifiers)

    case Map.get(context.index, key, []) do
      [] ->
        []

      [{other_labels, other_value}] ->
        {a, b} = if context.right_many?, do: {other_value, value}, else: {value, other_value}
        matched_pair(labels, other_labels, a, b, context)

      _ ->
        throw({:promql_error, :many_to_many_matching})
    end
  end

  defp unique_index(one, modifiers, side) do
    index = Enum.group_by(one, fn {labels, _} -> signature(labels, modifiers) end)

    if Enum.any?(index, fn {_, samples} -> length(samples) > 1 end),
      do: throw({:promql_error, {:many_to_many_matching, side}})

    index
  end

  defp matched_output({labels, _} = sample, seen, context) do
    key = signature(labels, context.modifiers)

    if is_nil(context.grouping) do
      # One-to-one cardinality belongs to matched inputs, before a comparison
      # can filter either sample out. Unmatched signatures do not participate.
      matched? = Map.has_key?(context.index, key)
      if matched? and MapSet.member?(seen, key), do: throw({:promql_error, :many_to_many_matching})
      seen = if matched?, do: MapSet.put(seen, key), else: seen
      {vector_pair(sample, context), seen}
    else
      output = vector_pair(sample, context)
      # Group modifiers may remove/overwrite a many-side label. Uniqueness is
      # then per matching group AND final output labels, after filtering; it is
      # distinct from an ambiguous one-side index or unrelated duplicate outputs.
      key = {key, Enum.map(output, &elem(&1, 0))}

      if output != [] and MapSet.member?(seen, key),
        do: throw({:promql_error, :multiple_matches_for_labels})

      seen = if output == [], do: seen, else: MapSet.put(seen, key)
      {output, seen}
    end
  end

  defp matched_pair(labels, other, a, b, context) do
    output_labels = result_labels(labels, other, context)

    cond do
      histogram?(a) or histogram?(b) or context.op in @trims ->
        histogram_pair(context.op, output_labels, a, b, context.boolean)

      filter?(context.op, context.boolean) ->
        filtered_sample(output_labels, a, Number.compare(context.op, a, b))

      true ->
        [{output_labels, result(context.op, a, b)}]
    end
  end

  defp result_labels(labels, other, context) do
    # Arithmetic removes the many-side name before explicit one-side label
    # inclusion. group_left/right(__name__) can therefore copy a name back.
    labels = if context.op in @comparisons or context.op in @trims, do: labels, else: Map.delete(labels, "__name__")
    labels = matched_labels(labels, other, context.modifiers, context.grouping)
    if context.boolean, do: Map.delete(labels, "__name__"), else: labels
  end

  defp matched_labels(labels, _other, modifiers, nil) do
    case matching(modifiers) do
      ["on", names] -> Map.take(labels, names)
      ["ignoring", names] -> Map.drop(labels, names)
      nil -> labels
    end
  end

  defp matched_labels(labels, other, _modifiers, grouping) do
    names =
      case grouping do
        [_, names] -> names
        _ -> []
      end

    Enum.reduce(names, labels, &include_label(&1, other, &2))
  end

  defp include_label(name, other, labels) do
    case Map.get(other, name, "") do
      "" -> Map.delete(labels, name)
      value -> Map.put(labels, name, value)
    end
  end

  defp set(op, modifiers, lhs, rhs) do
    left_keys = MapSet.new(lhs, fn {labels, _} -> signature(labels, modifiers) end)
    right_keys = MapSet.new(rhs, fn {labels, _} -> signature(labels, modifiers) end)

    case op do
      "and" -> Enum.filter(lhs, fn {labels, _} -> MapSet.member?(right_keys, signature(labels, modifiers)) end)
      "unless" -> Enum.reject(lhs, fn {labels, _} -> MapSet.member?(right_keys, signature(labels, modifiers)) end)
      "or" -> lhs ++ Enum.reject(rhs, fn {labels, _} -> MapSet.member?(left_keys, signature(labels, modifiers)) end)
    end
  end

  defp signature(labels, modifiers) do
    labels =
      case matching(modifiers) do
        ["on", names] -> Map.take(labels, names)
        ["ignoring", names] -> Map.drop(labels, ["__name__" | names])
        nil -> Map.delete(labels, "__name__")
      end

    Map.reject(labels, fn {_, value} -> value == "" end)
  end

  defp matching(modifiers), do: Enum.find(modifiers, &match?([mode, _] when mode in ["on", "ignoring"], &1))
  defp grouping(modifiers), do: Enum.find(modifiers, &match?([mode | _] when mode in ["group_left", "group_right"], &1))
  defp result(op, a, b) when op in @comparisons, do: if(Number.compare(op, a, b), do: 1.0, else: 0.0)
  defp result(op, a, b), do: Number.binary(op, a, b)

  def absent(vector, labels, steps) do
    vector = by_time(vector)
    at_steps(steps, fn ts -> if at(vector, ts) == [], do: [{labels, 1.0}], else: [] end)
  end

  def call("timestamp", [vector], _steps) do
    Enum.map(vector, fn {labels, samples} ->
      {Map.delete(labels, "__name__"), Enum.map(samples, fn {ts, _value} -> {ts, Time.seconds(ts)} end)}
    end)
  end

  def call("time", [], steps), do: [{%{}, Enum.map(steps, &{&1, Time.seconds(&1)})}]
  def call("pi", [], steps), do: [{%{}, Enum.map(steps, &{&1, :math.pi()})}]
  def call("vector", [scalar], _steps), do: scalar

  def call(name, [], steps) when name in ~w(start end step range) do
    value = Process.get(:promql_query_context) |> Map.fetch!(name)
    at_steps(steps, fn _ -> [{%{}, value}] end)
  end

  def call(name, [left, right], steps) when name in ["min_of", "max_of"] do
    left = by_time(left)
    right = by_time(right)
    at_steps(steps, fn ts -> [{%{}, Number.extremum(name, value(at(left, ts)), value(at(right, ts)))}] end)
  end

  def call(name, [], steps) when name in @calendar_functions, do: call(name, [call("time", [], steps)], steps)

  def call("scalar", [vector], steps) do
    vector = by_time(vector)

    at_steps(steps, fn ts ->
      floats = Enum.reject(at(vector, ts), fn {_, value} -> histogram?(value) end)
      [{%{}, scalar_value(floats)}]
    end)
  end

  def call("label_replace", [vector | args], _steps), do: vector |> LabelReplace.run(args) |> coalesce()

  def call(name, [vector | names], _steps) when name in ["sort_by_label", "sort_by_label_desc"] do
    names = Enum.map(names, fn {:string, name} -> name end)

    Enum.sort(vector, fn {left, _}, {right, _} ->
      {left, right} = if name == "sort_by_label_desc", do: {right, left}, else: {left, right}
      labels_before?(left, right, names)
    end)
  end

  def call("label_join", [vector, {:string, destination}, {:string, separator} | sources], _steps) do
    sources = Enum.map(sources, fn {:string, name} -> name end)
    count = length(sources)
    separator_bytes = max(0, count - 1) * byte_size(separator)

    vector
    |> Enum.map(fn {labels, samples} ->
      Evaluator.charge(:work, max(1, count))
      values = Enum.map(sources, &Map.get(labels, &1, ""))
      bytes = Enum.reduce(values, separator_bytes, &(byte_size(&1) + &2))
      # Reserve repeated source values and separators before constructing the
      # joined binary. All reads use the original labels, even when dst is src.
      Evaluator.charge(:work, bytes)
      joined = Enum.join(values, separator)
      labels = if joined == "", do: Map.delete(labels, destination), else: Map.put(labels, destination, joined)
      {labels, samples}
    end)
    |> coalesce()
  end

  def call("histogram_quantile", [quantile, buckets], steps) do
    quantile = by_time(quantile)
    buckets = buckets |> Histogram.parse_buckets() |> by_time()

    at_steps(steps, fn ts ->
      q = value(at(quantile, ts))
      Histogram.quantile(q, at(buckets, ts))
    end)
  end

  def call("histogram_quantiles", [vector, {:string, destination} | qs], steps) do
    vector = vector |> Histogram.parse_buckets() |> by_time()
    qs = Enum.map(qs, &by_time/1)

    at_steps(steps, fn ts ->
      Histogram.quantiles(at(vector, ts), destination, Enum.map(qs, &value(at(&1, ts))))
    end)
  end

  def call("histogram_fraction", [lower, upper, vector], steps) do
    {lower, upper, vector} = {by_time(lower), by_time(upper), vector |> Histogram.parse_buckets() |> by_time()}

    at_steps(steps, fn ts ->
      {l, u} = {value(at(lower, ts)), value(at(upper, ts))}
      Histogram.fraction(l, u, at(vector, ts))
    end)
  end

  def call(name, [vector], _steps) when name in @histogram_properties do
    property = Map.fetch!(@histogram_property_functions, name)

    for {labels, samples} <- vector,
        points = for({ts, h} <- samples, histogram?(h), do: {ts, histogram_property(property, h)}),
        points != [],
        do: {Map.delete(labels, "__name__"), points}
  end

  def call("clamp", [vector, lower, upper], steps) do
    {vector, lower, upper} = {by_time(vector), by_time(lower), by_time(upper)}

    at_steps(steps, fn ts ->
      {low, high} = {value(at(lower, ts)), value(at(upper, ts))}

      if Number.compare(">", low, high),
        do: [],
        else: transform_vector("clamp", at(vector, ts), {low, high})
    end)
  end

  def call(name, [vector | params], steps)
      when name in @calendar_functions or
             name in [
               "clamp_min",
               "clamp_max",
               "round",
               "abs",
               "sort",
               "sort_desc",
               "sgn",
               "floor",
               "ceil",
               "sqrt",
               "exp",
               "ln",
               "log2",
               "log10",
               "deg",
               "rad",
               "asin",
               "acos",
               "atan",
               "sin",
               "cos",
               "tan",
               "sinh",
               "cosh",
               "tanh",
               "asinh",
               "acosh",
               "atanh"
             ] do
    vector = by_time(vector)
    params = Enum.map(params, &by_time/1)
    at_steps(steps, fn ts -> transform_vector(name, at(vector, ts), parameter(params, ts)) end)
  end

  defp histogram_property(property, h) do
    if property in [:stddev, :stdvar] do
      Evaluator.charge(:work, 1 + length(h.positive_buckets) + length(h.negative_buckets) + length(h.custom_values))
    end

    apply(NativeHistogram, property, [h])
  end

  defp parameter([], _ts), do: 1.0
  defp parameter([scalar], ts), do: value(at(scalar, ts))
  defp scalar_value([{_, %HistogramSample{}}]), do: :nan
  defp scalar_value([{_, value}]), do: value
  defp scalar_value(_), do: :nan

  # These functions read floats; Prometheus leaves histograms out.
  defp transform_vector(name, vector, parameter),
    do: vector |> Enum.reject(fn {_, v} -> histogram?(v) end) |> transform_floats(name, parameter)

  defp transform_floats(vector, name, _parameter) when name in ["sort", "sort_desc"],
    do: sort(vector, name == "sort_desc")

  defp transform_floats(vector, name, parameter) do
    Enum.map(vector, fn {labels, value} -> {Map.delete(labels, "__name__"), transform(name, value, parameter)} end)
  end

  defp transform("clamp", v, {lower, upper}), do: v |> clamp(upper, :max) |> clamp(lower, :min)
  defp transform("clamp_min", v, p), do: clamp(v, p, :min)
  defp transform("clamp_max", v, p), do: clamp(v, p, :max)
  defp transform(name, v, _) when name in @calendar_functions, do: Time.calendar(name, v)
  defp transform("round", v, p), do: round_value(v, p)
  # Pre-rounded pi/180 and 180/pi, as in Prometheus's constant expressions.
  # Scale once: multiplying before dividing can overflow a finite conversion.
  defp transform("rad", v, _), do: Number.multiply(v, 0.017453292519943295)
  defp transform("deg", v, _), do: Number.multiply(v, 57.29577951308232)
  defp transform("asin", v, _) when is_number(v) and v >= -1 and v <= 1, do: :math.asin(v)
  defp transform("asin", _, _), do: :nan
  defp transform("acos", v, _) when is_number(v) and v >= -1 and v <= 1, do: :math.acos(v)
  defp transform("acos", _, _), do: :nan
  defp transform("atan", :nan, _), do: :nan
  defp transform("atan", :infinity, _), do: :math.pi() / 2
  defp transform("atan", :negative_infinity, _), do: -:math.pi() / 2
  defp transform("atan", v, _), do: :math.atan(v)

  defp transform(name, v, _) when name in ["sin", "cos", "tan"] and v in [:nan, :infinity, :negative_infinity], do: :nan

  defp transform("sin", v, _), do: :math.sin(v)
  defp transform("cos", v, _), do: :math.cos(v)
  defp transform("tan", v, _), do: :math.tan(v)
  defp transform("sinh", v, _) when v in [:nan, :infinity, :negative_infinity], do: v
  defp transform("cosh", :nan, _), do: :nan
  defp transform("cosh", v, _) when v in [:infinity, :negative_infinity], do: :infinity

  # Go math.Sinh/Cosh use Exp(abs(x))/2 above 21, including Exp's earlier
  # overflow. Platform sinh/cosh can still return finite values beyond it.
  defp transform(name, v, _) when name in ["sinh", "cosh"] and abs(v) > 21 do
    result = Number.multiply(exponential(abs(v)), 0.5)
    if name == "sinh" and v < 0, do: Number.negate(result), else: result
  end

  defp transform("sinh", v, _), do: :math.sinh(v)
  defp transform("cosh", v, _), do: :math.cosh(v)
  defp transform("tanh", :nan, _), do: :nan
  defp transform("tanh", :infinity, _), do: 1.0
  defp transform("tanh", :negative_infinity, _), do: -1.0
  defp transform("tanh", v, _), do: :math.tanh(v)
  defp transform("asinh", v, _) when v in [:nan, :infinity, :negative_infinity], do: v
  defp transform("asinh", v, _), do: :math.asinh(v)
  defp transform("acosh", :infinity, _), do: :infinity
  defp transform("acosh", v, _) when is_number(v) and v >= 1, do: :math.acosh(v)
  defp transform("acosh", _, _), do: :nan
  defp transform("atanh", v, _) when v == 1, do: :infinity
  defp transform("atanh", v, _) when v == -1, do: :negative_infinity
  defp transform("atanh", v, _) when is_number(v) and v > -1 and v < 1, do: :math.atanh(v)
  defp transform("atanh", _, _), do: :nan
  defp transform("floor", v, _) when is_number(v), do: :math.floor(v)
  defp transform("floor", v, _), do: v
  defp transform("ceil", v, _) when is_number(v), do: :math.ceil(v)
  defp transform("ceil", v, _), do: v
  defp transform("sqrt", v, _) when v in [:nan, :infinity], do: v
  defp transform("sqrt", v, _) when v == :negative_infinity or v < 0, do: :nan
  defp transform("sqrt", v, _), do: :math.sqrt(v)
  defp transform("exp", v, _) when v in [:nan, :infinity], do: v
  defp transform("exp", :negative_infinity, _), do: 0.0
  defp transform("exp", v, _), do: exponential(v)

  defp transform(name, v, _) when name in ["ln", "log2", "log10"] and v == 0, do: :negative_infinity
  defp transform(name, :infinity, _) when name in ["ln", "log2", "log10"], do: :infinity

  defp transform(name, v, _) when name in ["ln", "log2", "log10"] and (v in [:nan, :negative_infinity] or v < 0),
    do: :nan

  defp transform("ln", v, _), do: :math.log(v)
  defp transform("log2", v, _), do: binary_logarithm(v)
  defp transform("log10", v, _), do: :math.log10(v)
  defp transform("sgn", :nan, _), do: :nan
  defp transform("sgn", v, _) when v == 0, do: v
  defp transform("sgn", v, _), do: if(Number.compare("<", v, 0), do: -1.0, else: 1.0)
  defp transform("abs", :nan, _), do: :nan
  defp transform("abs", v, _), do: if(Number.sign(v) < 0, do: Number.negate(v), else: v)
  defp clamp(:nan, _, _), do: :nan
  defp clamp(_, :nan, _), do: :nan
  defp clamp(v, p, :min) when v == 0 and p == 0, do: if(Number.sign(v) == 1 or Number.sign(p) == 1, do: 0.0, else: -0.0)

  defp clamp(v, p, :max) when v == 0 and p == 0,
    do: if(Number.sign(v) == -1 or Number.sign(p) == -1, do: -0.0, else: 0.0)

  defp clamp(v, p, :min), do: Number.max(v, p)
  defp clamp(v, p, :max), do: Number.min(v, p)

  defp round_value(value, nearest) do
    inverse = Number.divide(1.0, nearest)
    rounded = Number.add(Number.multiply(value, inverse), 0.5)
    rounded = if is_number(rounded), do: :math.floor(rounded), else: rounded
    Number.divide(rounded, inverse)
  end

  # Adapted from Go 1.24.5 math/{log10.go,frexp.go,exp.go,exp_arm64.s}.
  # Copyright 2009, 2017 The Go Authors.
  # BSD license (also shipped in releases): priv/third_party/go-math-LICENSE.
  # The exp polynomial also retains its original permission notice:
  # Copyright (C) 2004 by Sun Microsystems, Inc. All rights reserved.
  # Permission to use, copy, modify, and distribute this software is freely
  # granted, provided that this notice is preserved.
  # Keep Go's reduction/scaling rather than libm: cancellation near log2(1)
  # and arm64 exponential underflow change observable PromQL predicates.
  defp binary_logarithm(value) do
    {value, adjustment} =
      if value < 2.2250738585072014e-308, do: {value * 4_503_599_627_370_496.0, -52}, else: {value, 0}

    <<0::1, exponent::11, fraction::52>> = <<value::float-64>>
    <<normalized::float-64>> = <<0::1, 1022::11, fraction::52>>
    exponent = exponent - 1022 + adjustment

    if normalized == 0.5 do
      exponent - 1.0
    else
      # Go arm64 fuses Log(frac)*(1/Ln2)+exp. Form the exact integer
      # numerator before the single float rounding; separate multiplication
      # and addition lose most significant digits immediately above one.
      <<1::1, log_exponent::11, log_fraction::52>> = <<:math.log(normalized)::float-64>>
      <<0::1, 1023::11, multiplier::52>> = <<1.4426950408889634::float-64>>
      denominator = Integer.pow(2, 1127 - log_exponent)
      product = (4_503_599_627_370_496 + log_fraction) * (4_503_599_627_370_496 + multiplier)
      (exponent * denominator - product) / denominator
    end
  end

  defp exponential(value) when value > 7.09782712893383973096e2, do: :infinity
  defp exponential(value) when value < -7.45133219101941108420e2, do: 0.0
  defp exponential(value) when abs(value) < 3.725290298461914e-9, do: 1.0 + value

  defp exponential(value) do
    exponent = trunc(1.44269504088896338700 * value + if(value < 0, do: -0.5, else: 0.5))
    hi = value - exponent * 6.93147180369123816490e-1
    lo = exponent * 1.90821492927058770002e-10
    remainder = hi - lo
    squared = remainder * remainder

    polynomial =
      1.66666666666666657415e-1 +
        squared *
          (-2.77777777770155933842e-3 +
             squared *
               (6.61375632143793436117e-5 +
                  squared * (-1.65339022054652515390e-6 + squared * 4.13813679705723846039e-8)))

    correction = remainder - squared * polynomial
    reduced = 1.0 - (lo - remainder * correction / (2.0 - correction) - hi)
    <<0::1, biased::11, fraction::52>> = <<reduced::float-64>>
    biased = biased + exponent

    cond do
      biased >= 2047 ->
        :infinity

      biased < 1 ->
        # This is specifically the pinned Go arm64 52-bit scaling, including
        # its early zero results at the smallest-subnormal boundary.
        <<scaled::float-64>> = <<0::1, biased + 52::11, fraction::52>>
        scaled * 2.220446049250313e-16

      true ->
        <<scaled::float-64>> = <<0::1, biased::11, fraction::52>>
        scaled
    end
  end

  def parameter_aggregate("count_values", grouping, {:string, name}, vector, steps) do
    vector = by_time(vector)

    at_steps(steps, fn ts ->
      vector
      |> at(ts)
      |> Enum.reduce(%{}, fn {labels, sample}, counts ->
        text = value_text(sample)
        # Charge generated-label bytes before constructing its label map.
        Evaluator.charge(:work, byte_size(name) + IO.iodata_length(text))
        labels = labels |> group_key(grouping) |> Map.put(name, IO.iodata_to_binary(text))
        Map.update(counts, labels, 1.0, &(&1 + 1.0))
      end)
      |> Map.to_list()
    end)
  end

  def parameter_aggregate("quantile", grouping, parameter, vector, steps) do
    parameter = by_time(parameter)
    vector = by_time(vector)

    at_steps(steps, fn ts ->
      q = value(at(parameter, ts))
      Evaluator.quantile_warning(q)
      {histograms, floats} = Enum.split_with(at(vector, ts), fn {_, v} -> histogram?(v) end)
      if histograms != [], do: Evaluator.info("PromQL info: ignored histogram in quantile aggregation")

      floats
      |> Enum.group_by(fn {labels, _} -> group_key(labels, grouping) end, fn {_, v} -> %{value: v} end)
      |> Enum.map(fn {labels, samples} ->
        count = length(samples)
        Evaluator.charge(:work, count * length(Integer.digits(count, 2)))
        {labels, RangeMath.quantile(q, samples)}
      end)
    end)
  end

  def parameter_aggregate(op, grouping, parameter, vector, steps) when op in ["limitk", "limit_ratio"] do
    parameter = by_time(parameter)

    {parameters, _} =
      Enum.map_reduce(steps, MapSet.new(), fn ts, seen ->
        {parameter, seen} = sampling_parameter(op, value(at(parameter, ts)), seen)
        {{ts, parameter}, seen}
      end)

    parameters = Map.new(parameters)

    # Hash every complete label set once, independently of values, groups and
    # steps. Never reuse the storage fingerprint, including after label rewrites.
    hashes =
      Map.new(vector, fn {labels, _} ->
        bytes = Enum.reduce(labels, 0, fn {k, v}, n -> n + byte_size(k) + byte_size(v) + 8 end)
        Evaluator.charge(:work, bytes + map_size(labels) * length(Integer.digits(map_size(labels) + 1, 2)))
        {labels, LabelHash.hash(labels)}
      end)

    vector = if op == "limitk", do: sampling_order(vector, hashes), else: vector
    vector = by_time(vector)

    at_steps(steps, fn ts ->
      samples = at(vector, ts)
      Evaluator.charge(:work, Enum.reduce(samples, 1, fn {labels, _}, n -> n + map_size(labels) end))
      sampling_step(op, grouping, Map.fetch!(parameters, ts), samples, hashes)
    end)
  end

  def parameter_aggregate(op, grouping, parameter, vector, steps) do
    parameter = by_time(parameter)
    vector = by_time(vector)
    at_steps(steps, fn ts -> topk_step(op, grouping, value(at(parameter, ts)), at(vector, ts)) end)
  end

  defp sampling_parameter("limitk", k, seen) do
    if not is_number(k) or k <= -9_223_372_036_854_775_808 or k >= 9_223_372_036_854_775_808,
      do: throw({:promql_error, :invalid_aggregation_parameter})

    {max(0, trunc(k)), seen}
  end

  defp sampling_parameter("limit_ratio", :nan, _), do: throw({:promql_error, :invalid_aggregation_parameter})

  defp sampling_parameter("limit_ratio", ratio, seen) do
    capped =
      cond do
        Number.compare(">", ratio, 1) -> 1.0
        Number.compare("<", ratio, -1) -> -1.0
        true -> ratio
      end

    if capped != ratio and not MapSet.member?(seen, capped) do
      Evaluator.ratio_warning(ratio, capped)
      {capped, MapSet.put(seen, capped)}
    else
      {capped, seen}
    end
  end

  defp sampling_order(vector, hashes) do
    count = length(vector)

    bytes =
      Enum.reduce(vector, 0, fn {labels, _}, n ->
        Enum.reduce(labels, n + 1, fn {k, v}, n -> n + byte_size(k) + byte_size(v) end)
      end)

    Evaluator.charge(:work, (count + bytes) * length(Integer.digits(count + 1, 2)))
    Enum.sort_by(vector, fn {labels, _} -> {Map.fetch!(hashes, labels), labels} end)
  end

  defp sampling_step("limitk", grouping, k, samples, _) do
    samples
    |> Enum.group_by(fn {labels, _} -> group_key(labels, grouping) end)
    |> Enum.flat_map(fn {_, values} -> Enum.take(values, k) end)
  end

  defp sampling_step("limit_ratio", _, ratio, samples, hashes) do
    Enum.filter(samples, fn {labels, _} ->
      offset = Map.fetch!(hashes, labels) / 18_446_744_073_709_551_616
      if ratio >= 0, do: offset < ratio, else: offset >= 1.0 + ratio
    end)
  end

  defp value_text(%HistogramSample{} = h) do
    Evaluator.charge(:work, 1 + length(h.positive_buckets) + length(h.negative_buckets) + length(h.custom_values))
    NativeHistogram.value_text(h)
  end

  defp value_text(value), do: Number.format(value, :fixed)

  defp topk_step(op, _grouping, :nan, _vector) when op in ["topk", "bottomk"] do
    throw({:promql_error, {:invalid_ranking_parameter, op, :nan}})
  end

  defp topk_step(op, grouping, k, vector) do
    k = rank_count(k)

    if k == 0 do
      []
    else
      {histograms, floats} = Enum.split_with(vector, fn {_, v} -> histogram?(v) end)
      if histograms != [], do: Evaluator.info("PromQL info: ignored histogram in #{op} aggregation")

      floats
      |> Enum.group_by(fn {labels, _} -> group_key(labels, grouping) end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_, values} -> values |> sort(op == "topk") |> Enum.take(k) end)
    end
  end

  defp rank_count(k) do
    cond do
      Number.compare("<", k, 1) -> 0
      not is_number(k) or k >= 9_223_372_036_854_775_808 -> throw({:promql_error, :invalid_aggregation_parameter})
      true -> trunc(k)
    end
  end

  def group_key(_, nil), do: %{}
  def group_key(labels, {:grouping, :by, names}), do: Map.take(labels, names)
  def group_key(labels, {:grouping, :without, names}), do: Map.drop(labels, ["__name__" | names])

  defp labels_before?(left, right, []) do
    bytes = Enum.reduce(left, 0, fn {k, v}, sum -> sum + byte_size(k) + byte_size(v) + 1 end)
    bytes = Enum.reduce(right, bytes, fn {k, v}, sum -> sum + byte_size(k) + byte_size(v) + 1 end)
    Evaluator.charge(:work, max(1, bytes))
    Enum.sort(left) <= Enum.sort(right)
  end

  defp labels_before?(left, right, [name | names]) do
    a = Map.get(left, name, "")
    b = Map.get(right, name, "")
    Evaluator.charge(:work, 1 + byte_size(name) + byte_size(a) + byte_size(b))

    if a == b do
      labels_before?(left, right, names)
    else
      # Match the pinned dependency's ASCII digit chunks and int64 overflow
      # fallback. Its empty/leading-zero comparisons are not a total order.
      natural_before?(Regex.scan(~r/[0-9]+|[^0-9]+/, a), Regex.scan(~r/[0-9]+|[^0-9]+/, b))
    end
  end

  defp natural_before?([], _), do: false
  defp natural_before?(_, []), do: false

  defp natural_before?([[a] | rest_a], [[b] | rest_b]) do
    {a, b} =
      case {natural_integer(a), natural_integer(b)} do
        {{:ok, a}, {:ok, b}} -> {a, b}
        _ -> {a, b}
      end

    cond do
      a != b -> a < b
      rest_a == [] -> true
      rest_b == [] -> false
      true -> natural_before?(rest_a, rest_b)
    end
  end

  defp natural_integer(chunk) do
    # Trim before parsing so arbitrarily long zero prefixes never allocate
    # an exponent-sized integer. Overflowing digit runs compare lexically.
    digits = String.trim_leading(chunk, "0")

    with true <- byte_size(digits) <= 19,
         {value, ""} when value <= 9_223_372_036_854_775_807 <- Integer.parse(if(digits == "", do: "0", else: digits)) do
      {:ok, value}
    else
      _ -> :overflow
    end
  end

  def sort(values, descending?) do
    Enum.sort(values, fn {la, a}, {lb, b} ->
      cond do
        a == b -> la <= lb
        a == :nan -> false
        b == :nan -> true
        descending? -> Number.less?(b, a)
        true -> Number.less?(a, b)
      end
    end)
  end

  defp value([{_, value}]), do: value
  defp at(index, ts), do: Map.get(index, ts, [])

  # Each step's samples in series order, built without an intermediate list
  # of every sample.
  defp by_time(series) do
    {index, count} =
      series
      |> Enum.reverse()
      |> Enum.reduce({%{}, 0}, fn {labels, samples}, acc ->
        Enum.reduce(samples, acc, &index_sample(labels, &1, &2))
      end)

    Evaluator.charge(:work, count)
    index
  end

  defp index_sample(labels, {ts, value}, {index, count}) do
    case index do
      %{^ts => rows} -> {%{index | ts => [{labels, value} | rows]}, count + 1}
      _ -> {Map.put(index, ts, [{labels, value}]), count + 1}
    end
  end

  defp at_steps(steps, fun) do
    rows =
      Enum.flat_map(steps, fn ts ->
        values = fun.(ts) |> unique!()
        Evaluator.charge(:work, length(values))
        for {labels, value} <- values, do: {labels, {ts, value}}
      end)

    # Preserve operation ordering for instant topk/sort results.
    order = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    groups = Enum.group_by(rows, &elem(&1, 0), &elem(&1, 1))
    Enum.map(order, &{&1, Map.fetch!(groups, &1)})
  end

  # Metric-name removal may merge disjoint series in a range response.
  # Only identical labels at the SAME evaluation step are a PromQL error.
  def coalesce(series) do
    rows = for {labels, samples} <- series, {ts, value} <- samples, do: {{labels, ts}, value}
    Evaluator.charge(:work, length(rows))
    if length(rows) != map_size(Map.new(rows)), do: throw({:promql_error, :duplicate_result_label_sets})
    order = Enum.uniq_by(series, &elem(&1, 0)) |> Enum.map(&elem(&1, 0))
    groups = Enum.group_by(rows, fn {{labels, _}, _} -> labels end, fn {{_, ts}, value} -> {ts, value} end)
    Enum.map(order, &{&1, Enum.sort(Map.fetch!(groups, &1))})
  end

  defp unique!(values) do
    if length(values) != length(Enum.uniq_by(values, &elem(&1, 0))),
      do: throw({:promql_error, :duplicate_result_label_sets})

    values
  end
end
