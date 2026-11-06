defmodule Pulse.Traces.MetricExpression do
  @moduledoc false

  alias Pulse.LogQL.Quantity
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number

  @comparisons ~w(= != < <= > >=)
  @numeric ~r/\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z/

  # Pipeline parsing remains owned by Metrics; this module owns composition.
  def parse(text, pipeline) do
    text = String.replace(text, ~r/\s+with\s*\([^()]*\)\s*\z/, "")
    ast = node(String.trim(text), pipeline, 0)
    leaves = ast |> leaves() |> Enum.uniq()
    if size(ast) > 128 or length(leaves) > 16, do: fail(:query_expression_limit)

    case ast do
      {:leaf, query} -> {:ok, query}
      {:constant, _, _} -> fail()
      _ -> {:ok, %{expression: ast, leaves: leaves}}
    end
  catch
    {:metric_expression, reason} -> {:error, reason}
  end

  defp node(_text, _pipeline, depth) when depth > 32, do: fail(:query_expression_limit)

  defp node(text, pipeline, depth) do
    case prefilter_ranking(text, pipeline, depth) do
      {:ok, leaf} -> leaf
      :none -> composition(text, pipeline, depth)
    end
  end

  # Only one scalar filter on a single, otherwise unranked pipeline may
  # precede ranking. Keep it in the native leaf so filtering happens before
  # the existing native select-k, never as a reordered BEAM post-filter.
  defp prefilter_ranking(text, pipeline, depth) do
    with [_, prefix, rank, k] <-
           Regex.run(~r/\A(\{.*)\s*\|\s*(topk|bottomk)\s*\(\s*([0-9]{1,6})\s*\)\z/s, text),
         true <- Enum.any?(operators(prefix), fn {_, op} -> op in @comparisons end),
         k = String.to_integer(k),
         true <- k > 0 do
      case node(String.trim(prefix), pipeline, depth + 1) do
        {:filter, op, {:leaf, %{second: nil} = query}, threshold} when is_number(threshold) ->
          {:ok, {:leaf, %{query | second: {rank, k, {op, threshold}}}}}

        _ ->
          fail()
      end
    else
      _ -> :none
    end
  end

  defp composition(text, pipeline, depth) do
    ops = operators(text)

    case choose(ops) do
      {at, op} ->
        if String.starts_with?(text, "{") and op not in @comparisons, do: fail()
        left = binary_part(text, 0, at) |> String.trim()
        right = binary_part(text, at + byte_size(op), byte_size(text) - at - byte_size(op)) |> String.trim()
        combine(op, node(left, pipeline, depth + 1), node(right, pipeline, depth + 1))

      nil ->
        atom(text, pipeline, depth)
    end
  end

  defp atom("(" <> rest, pipeline, depth) do
    if not String.ends_with?(rest, ")"), do: fail()
    binary_part(rest, 0, byte_size(rest) - 1) |> String.trim() |> node(pipeline, depth + 1)
  end

  defp atom("{" <> _ = text, pipeline, _depth) do
    case pipeline.(text) do
      {:ok, query} -> {:leaf, query}
      {:error, reason} -> fail(reason)
    end
  end

  defp atom("-" <> rest, pipeline, depth) do
    rest = String.trim(rest)

    if Regex.match?(~r/\A[0-9]+\z/, rest) do
      integer_literal("-" <> rest)
    else
      case node(rest, pipeline, depth + 1) do
        {:constant, :integer, value} -> integer(Number.negate(value))
        {:constant, type, value} -> {:constant, type, Number.negate(value)}
        _ -> fail()
      end
    end
  end

  defp atom(text, _pipeline, _depth) do
    cond do
      Regex.match?(~r/\A[+]?[0-9]+\z/, text) ->
        integer_literal(text)

      Regex.match?(@numeric, text) ->
        case FloatParser.parse(text) do
          {:ok, value} -> {:constant, :float, value}
          :error -> fail()
        end

      true ->
        case Quantity.duration(text) do
          {:ok, ns} -> {:constant, :duration, ns / 1_000_000_000}
          :error -> fail()
        end
    end
  end

  defp integer_literal(text) do
    if byte_size(text) > 20, do: fail()
    integer(String.to_integer(text))
  end

  defp integer(value) when value >= -9_223_372_036_854_775_808 and value <= 9_223_372_036_854_775_807,
    do: {:constant, :integer, value}

  defp integer(_value), do: fail()

  defp combine(op, left, {:constant, _, value}) when op in @comparisons do
    if constant?(left), do: fail()
    {:filter, op, left, float(value)}
  end

  defp combine(op, _left, _right) when op in @comparisons, do: fail()
  defp combine(_op, {:constant, :duration, _}, _), do: fail()
  defp combine(_op, _, {:constant, :duration, _}), do: fail()

  defp combine("/", {:constant, :integer, _}, {:constant, :integer, 0}), do: fail()

  defp combine("/", {:constant, :integer, a}, {:constant, :integer, b}), do: integer(div(a, b))

  defp combine(op, {:constant, :integer, a}, {:constant, :integer, b}), do: integer(Number.binary(op, a, b))

  defp combine(op, {:constant, _, a}, {:constant, _, b}), do: {:constant, :float, Number.binary(op, float(a), float(b))}

  defp combine(op, a, b), do: {:binary, op, a, b}

  defp constant?({:constant, _, _}), do: true
  defp constant?(_), do: false
  defp float(value) when is_number(value), do: value / 1
  defp float(value), do: value

  defp choose(ops) do
    Enum.reduce(ops, nil, fn {_, op} = candidate, current ->
      if current == nil or precedence(op) <= precedence(elem(current, 1)), do: candidate, else: current
    end)
  end

  defp precedence(op) when op in @comparisons, do: 0
  defp precedence(op) when op in ["+", "-"], do: 1
  defp precedence(_op), do: 2

  # Only top-level operators count. Selectors, strings and function calls are
  # opaque here, including escaped quotes and arithmetic-looking attribute text.
  defp operators(text), do: operators(text, 0, 0, 0, false, nil, [])
  defp operators(<<>>, _at, 0, 0, false, _previous, ops), do: Enum.reverse(ops)
  defp operators(<<>>, _at, _parens, _braces, _quoted, _previous, _ops), do: fail()

  defp operators(<<"\\", _c, rest::binary>>, at, p, b, true, previous, ops),
    do: operators(rest, at + 2, p, b, true, previous, ops)

  defp operators(<<?", rest::binary>>, at, p, b, q, previous, ops),
    do: operators(rest, at + 1, p, b, not q, previous, ops)

  defp operators(<<_c, rest::binary>>, at, p, b, true, previous, ops),
    do: operators(rest, at + 1, p, b, true, previous, ops)

  defp operators(<<c, rest::binary>>, at, p, b, false, _previous, ops) when c in [?(, ?), ?{, ?}] do
    {p, b} =
      case c do
        ?( -> {p + 1, b}
        ?) -> {p - 1, b}
        ?{ -> {p, b + 1}
        ?} -> {p, b - 1}
      end

    if p < 0 or b < 0, do: fail()
    operators(rest, at + 1, p, b, false, c, ops)
  end

  defp operators(<<c, rest::binary>>, at, 0, 0, false, previous, ops) when c in ~c"+-*/=<>!" do
    {op, rest} =
      case {c, rest} do
        {c, <<"=", tail::binary>>} when c in ~c"=<>!" -> {<<c, ?=>>, tail}
        _ -> {<<c>>, rest}
      end

    if op in ["!", "=="], do: fail()
    unary = c in ~c"+-" and previous in [nil, ?+, ?-, ?*, ?/, ?=, ?<, ?>, ?e, ?E]
    ops = if unary, do: ops, else: [{at, op} | ops]
    operators(rest, at + byte_size(op), 0, 0, false, c, ops)
  end

  defp operators(<<c, rest::binary>>, at, p, b, false, previous, ops),
    do: operators(rest, at + 1, p, b, false, if(c in ~c" \t\r\n", do: previous, else: c), ops)

  defp leaves({:leaf, query}), do: [query]
  defp leaves({:constant, _, _}), do: []
  defp leaves({:filter, _, child, _}), do: leaves(child)
  defp leaves({:binary, _, left, right}), do: leaves(left) ++ leaves(right)
  defp size({:binary, _, left, right}), do: 1 + size(left) + size(right)
  defp size({:filter, _, child, _}), do: 1 + size(child)
  defp size({:leaf, %{second: {_, _, {_, _}}}}), do: 3
  defp size(_), do: 1

  # Native leaves retain complete slots off heap. Arithmetic lives here so it
  # shares the BEAM worker's deadline/heap and has one IEEE implementation.
  def finish(%{expression: ast, leaves: queries}, packed, window) do
    leaves = Map.new(Enum.zip_with(queries, packed, &{&1, decode(&2)}))
    {series, _work} = evaluate(ast, leaves, 0)
    result = %{"series" => serialize(series, window)} |> Pulse.JSON.encode!()
    if byte_size(result) > 64 * 1024 * 1024, do: fail(:query_resource_limit)
    {:ok, result}
  catch
    {:metric_expression, reason} -> {:error, reason}
  end

  defp decode(series) do
    Map.new(series, fn {labels, packed} ->
      labels = Enum.map(labels, fn {key, value} -> {key, Pulse.JSON.decode!(value)} end)
      values = for <<bits::64 <- packed>>, do: number(bits)
      {key(labels), {labels, values}}
    end)
  end

  defp number(bits) do
    case <<bits::64>> do
      <<_::1, 2047::11, fraction::52>> when fraction != 0 -> :nan
      <<0::1, 2047::11, 0::52>> -> :infinity
      <<1::1, 2047::11, 0::52>> -> :negative_infinity
      <<value::float-64>> -> value
    end
  end

  defp evaluate({:leaf, query}, leaves, work), do: {Map.fetch!(leaves, query), work}
  defp evaluate({:constant, _, value}, _leaves, work), do: {{:scalar, float(value)}, work}

  defp evaluate({:filter, op, child, threshold}, leaves, work) do
    {series, work} = evaluate(child, leaves, work)
    work = charge(series, work)

    result =
      Map.new(series, fn {key, {labels, values}} ->
        values = Enum.map(values, &if(matches?(op, &1, threshold), do: &1, else: :nan))
        {key, {labels, values}}
      end)
      |> Map.reject(fn {_, {_, values}} -> Enum.all?(values, &Number.nan?/1) end)

    {result, work}
  end

  defp evaluate({:binary, op, left, right}, leaves, work) do
    {left, work} = evaluate(left, leaves, work)
    {right, work} = evaluate(right, leaves, work)
    binary(op, left, right, work)
  end

  defp binary(op, {:scalar, scalar}, series, work), do: scale(series, work, &arithmetic(op, scalar, &1))

  defp binary(op, series, {:scalar, scalar}, work), do: scale(series, work, &arithmetic(op, &1, scalar))

  defp binary(op, left, right, work) do
    target = if Map.has_key?(right, []), do: left, else: right
    work = charge(target, work)

    result =
      Enum.reduce(target, %{}, fn {key, _}, output ->
        with {l, lv} <- Map.get(left, key, left[[]]),
             {r, rv} <- Map.get(right, key, right[[]]) do
          labels = merge_labels(op, l, r)
          Map.put(output, key, {labels, Enum.zip_with(lv, rv, &arithmetic(op, &1, &2))})
        else
          nil -> output
        end
      end)

    {result, work}
  end

  defp scale(series, work, fun) do
    work = charge(series, work)
    {Map.new(series, fn {key, {labels, values}} -> {key, {labels, Enum.map(values, fun)}} end), work}
  end

  defp charge(series, work) do
    points = Enum.sum_by(series, fn {_, {_, values}} -> length(values) end)
    if points > 2_000_000, do: fail(:query_sample_limit)
    if work + points > 20_000_000, do: fail(:query_work_limit)
    work + points
  end

  defp arithmetic("/", _a, b) when b == 0, do: :nan
  defp arithmetic(op, a, b), do: Number.binary(op, a, b)
  defp matches?(_op, :nan, _threshold), do: false
  defp matches?(op, value, threshold), do: Number.compare(if(op == "=", do: "==", else: op), value, threshold)
  defp key(labels), do: Enum.reject(labels, &(elem(&1, 0) == "__name__"))

  defp merge_labels(op, left, right) do
    name = fn labels -> labels |> List.keyfind("__name__", 0, {nil, nil}) |> elem(1) end
    names = {name.(left), name.(right)}
    labels = left ++ Enum.reject(right, fn {k, _} -> k == "__name__" or List.keymember?(left, k, 0) end)

    case names do
      {%{"stringValue" => a}, %{"stringValue" => b}} ->
        List.keyreplace(labels, "__name__", 0, {"__name__", %{"stringValue" => "(#{a} #{op} #{b})"}})

      _ ->
        key(labels)
    end
  end

  defp serialize(series, {start, _finish, step, instant}) do
    series
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_, {labels, values}} ->
      samples =
        values
        |> Enum.with_index()
        |> Enum.reject(fn {value, _} -> Number.nan?(value) end)
        |> Enum.map(fn {value, i} ->
          %{"timestampMs" => to_string(div(start + (i + 1) * step, 1_000_000)), "value" => json_number(value)}
        end)

      labels = Enum.map(labels, fn {k, v} -> %{"key" => k, "value" => v} end)

      case {instant, samples} do
        {_, []} -> []
        {true, [sample | _]} -> [%{"labels" => labels, "value" => sample["value"]}]
        {false, _} -> [%{"labels" => labels, "samples" => samples}]
      end
    end)
  end

  defp json_number(:infinity), do: "Infinity"
  defp json_number(:negative_infinity), do: "-Infinity"
  defp json_number(value), do: value
  defp fail(reason \\ :unsupported_trace_selector), do: throw({:metric_expression, reason})
end
