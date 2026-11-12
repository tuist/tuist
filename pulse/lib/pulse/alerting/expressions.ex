defmodule Pulse.Alerting.Expressions do
  @moduledoc "Bounded, pure expression graph execution over explicit source frames. Does not enable Grafana imports."
  alias Pulse.Alerting.Expressions.Math
  alias Pulse.Alerting.Graph
  alias Pulse.Alerting.Rule
  alias Pulse.PromQL.Number

  @operators %{"gt" => ">", "lt" => "<", "eq" => "==", "ne" => "!=", "gte" => ">=", "lte" => "<="}
  @max_frames 1024
  @max_points 100_000
  @max_work 1_000_000
  @max_label_bytes 1_048_576

  def compile(original) do
    with :ok <- Graph.validate(original),
         {:ok, nodes, size} <- compile_nodes(original["data"]),
         true <- size <= 4096,
         {:ok, ordered} <- order(nodes, MapSet.new(), []),
         terminal = terminal(original),
         true <- is_binary(terminal) do
      {:ok,
       %{nodes: ordered, sources: Enum.map(Enum.filter(ordered, &(&1.op == :source)), & &1.ref), terminal: terminal}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_expression_graph}
    end
  rescue
    _ -> {:error, :invalid_expression_graph}
  end

  defp terminal(%{"record" => %{"from" => ref}}), do: ref
  defp terminal(original), do: original["condition"]

  defp compile_nodes(nodes) do
    Enum.reduce_while(nodes, {:ok, [], 0}, fn node, {:ok, acc, size} ->
      case compile_node(node) do
        {:ok, op, deps, count} -> {:cont, {:ok, [%{ref: node["refId"], op: op, deps: deps} | acc], size + count}}
        {:error, reason} -> {:halt, {:error, {:expression_node, node["refId"], reason}}}
      end
    end)
  end

  defp compile_node(node) do
    if node["datasourceUid"] in ["__expr__", "-100"] or node["source_type"] == "expression",
      do: compile_model(node["model"]),
      else: {:ok, :source, [], 1}
  end

  defp compile_model(%{"type" => "math", "expression" => text}) do
    with {:ok, ast, size, refs} <- Math.parse(text), do: {:ok, {:math, ast}, refs, size}
  end

  defp compile_model(%{"type" => "reduce", "expression" => ref, "reducer" => "last"} = model) do
    if model["settings"] in [nil, %{}, %{"mode" => "strict"}],
      do: {:ok, {:last, ref}, [ref], 1},
      else: {:error, :unsupported_reduce_mode}
  end

  defp compile_model(%{"type" => "threshold", "expression" => ref, "conditions" => [condition]})
       when is_map(condition) do
    with %{"type" => op, "params" => [number]} <- condition["evaluator"],
         true <- Map.has_key?(@operators, op) and is_number(number),
         true <- condition["unloadEvaluator"] == nil and condition["loadedDimensions"] == nil do
      {:ok, {:threshold, ref, @operators[op], number / 1}, [ref], 1}
    else
      _ -> {:error, :unsupported_threshold}
    end
  end

  defp compile_model(_), do: {:error, :unsupported_expression}

  defp order([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp order(nodes, seen, acc) do
    case Enum.split_with(nodes, fn node -> Enum.all?(node.deps, &MapSet.member?(seen, &1)) end) do
      {[], _} ->
        {:error, :invalid_expression_graph}

      {ready, remaining} ->
        order(remaining, Enum.reduce(ready, seen, &MapSet.put(&2, &1.ref)), Enum.reverse(ready, acc))
    end
  end

  @doc "Inputs are ref-keyed {:scalar, value}, {:numbers, frames}, or {:series, frames}; frames have atom labels/value or points keys."
  def execute(original, inputs, opts \\ [])

  def execute(original, inputs, opts) when is_map(inputs) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- Keyword.keys(opts) -- [:deadline] == [],
         deadline = Keyword.get(opts, :deadline, System.monotonic_time(:millisecond) + 1000),
         true <- is_integer(deadline),
         {:ok, plan} <- compile(original),
         true <- Enum.sort(Map.keys(inputs)) == Enum.sort(plan.sources),
         {:ok, inputs} <- validate_inputs(inputs),
         budget = %{
           work: 0,
           points: 0,
           deadline: deadline
         },
         {:ok, results, notices, _} <- run(plan.nodes, inputs, %{}, [], budget) do
      {:ok, %{terminal: results[plan.terminal], values: results, notices: Enum.reverse(notices)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_expression_inputs}
    end
  end

  def execute(_, _, _), do: {:error, :invalid_expression_inputs}

  defp validate_inputs(inputs) do
    Enum.reduce_while(inputs, {:ok, %{}, 0, 0, 0}, fn {ref, frames}, {:ok, acc, n, p, bytes} ->
      case validate_set(frames) do
        {:ok, clean, count, points, label_bytes}
        when n + count <= @max_frames and p + points <= @max_points and bytes + label_bytes <= @max_label_bytes ->
          {:cont, {:ok, Map.put(acc, ref, clean), n + count, p + points, bytes + label_bytes}}

        _ ->
          {:halt, {:error, :expression_input_limit}}
      end
    end)
    |> case do
      {:ok, clean, _, _, _} -> {:ok, clean}
      error -> error
    end
  end

  defp validate_set({:scalar, value}) do
    if value?(value), do: {:ok, {:scalar, float_value(value)}, 1, 1, 0}, else: :error
  end

  defp validate_set({type, frames})
       when type in [:numbers, :series] and is_list(frames) and length(frames) <= @max_frames do
    Enum.reduce_while(frames, {:ok, [], 0, 0}, &validate_frame(&1, &2, type))
    |> case do
      {:ok, clean, points, bytes} -> {:ok, {type, Enum.reverse(clean)}, length(frames), points, bytes}
      error -> error
    end
  end

  defp validate_set(_), do: :error

  defp validate_frame(frame, {:ok, acc, points, bytes}, type) do
    with %{labels: labels} <- frame,
         true <- Rule.labels?(labels),
         true <- Enum.sort(Map.keys(frame)) == frame_keys(type),
         {:ok, count} <- frame_values(type, frame),
         true <- points + count <= @max_points,
         size = Enum.reduce(labels, 0, fn {k, v}, n -> n + byte_size(k) + byte_size(v) end),
         true <- bytes + size <= @max_label_bytes do
      clean =
        frame
        |> Map.put(:labels, Map.new(labels, fn {k, v} -> {:binary.copy(k), :binary.copy(v)} end))
        |> normalize_values(type)

      {:cont, {:ok, [clean | acc], points + count, bytes + size}}
    else
      _ -> {:halt, :error}
    end
  end

  defp frame_keys(:numbers), do: [:labels, :value]
  defp frame_keys(:series), do: [:labels, :points]
  defp normalize_values(frame, :numbers), do: Map.update!(frame, :value, &float_value/1)

  defp normalize_values(frame, :series),
    do: Map.update!(frame, :points, &Enum.map(&1, fn {t, v} -> {t, float_value(v)} end))

  defp float_value(value) when is_integer(value), do: value / 1
  defp float_value(value), do: value

  defp frame_values(:numbers, %{value: value}), do: if(value?(value), do: {:ok, 1}, else: :error)

  defp frame_values(:series, %{points: points}) when is_list(points) and length(points) <= @max_points do
    result =
      Enum.reduce_while(points, -1, fn
        {time, value}, previous
        when is_integer(time) and time >= 0 and time <= 9_223_372_036_854_775_807 and time > previous ->
          if value?(value), do: {:cont, time}, else: {:halt, :error}

        _, _ ->
          {:halt, :error}
      end)

    if result == :error, do: :error, else: {:ok, length(points)}
  end

  defp frame_values(_, _), do: :error
  defp value?(nil), do: true

  defp value?(value) when is_integer(value),
    do: value >= -9_223_372_036_854_775_808 and value <= 9_223_372_036_854_775_807

  defp value?(value), do: Number.valid?(value) and value != :stale

  defp run([], _, results, notices, budget), do: {:ok, results, notices, budget}

  defp run([node | remaining], inputs, results, notices, budget) do
    with {:ok, budget} <- charge(budget, 1, 0),
         {:ok, frames, dropped, budget} <- evaluate(node.op, inputs[node.ref], results, budget),
         {:ok, budget} <- charge(budget, 0, if(node.op == :source, do: point_count(frames), else: 0)) do
      notices = if dropped == 0, do: notices, else: [%{ref: node.ref, dropped: dropped} | notices]
      run(remaining, inputs, Map.put(results, node.ref, frames), notices, budget)
    end
  end

  defp point_count({:scalar, _}), do: 1
  defp point_count({:numbers, frames}), do: length(frames)
  defp point_count({:series, frames}), do: Enum.reduce(frames, 0, fn frame, count -> count + length(frame.points) end)
  defp evaluate(:source, inputs, _, budget), do: {:ok, inputs, 0, budget}
  defp evaluate({:math, ast}, _, results, budget), do: math(ast, results, budget)

  defp evaluate({:last, ref}, _, results, budget) do
    with {:ok, budget} <- charge(budget, point_count(results[ref]), 0), do: reduce_last(results[ref], budget)
  end

  defp evaluate({:threshold, ref, op, threshold}, _, results, budget) do
    with {:ok, budget} <- charge(budget, point_count(results[ref]), point_count(results[ref])),
         do: {:ok, map_values(results[ref], &threshold(&1, op, threshold)), 0, budget}
  end

  defp reduce_last(frames, budget) do
    case frames do
      {:series, frames} ->
        with {:ok, budget} <- charge(budget, 0, length(frames)),
             do:
               {:ok, {:numbers, Enum.map(frames, fn frame -> %{labels: frame.labels, value: last(frame.points)} end)},
                0, budget}

      {:numbers, _} = frames ->
        {:ok, frames, 0, budget}

      {:scalar, _} = frames ->
        {:ok, frames, 0, budget}
    end
  end

  defp last([]), do: :nan
  defp last(points), do: points |> List.last() |> elem(1)
  defp threshold(nil, _, _), do: nil
  defp threshold(value, op, threshold), do: boolean(Number.compare(op, value, threshold))
  defp boolean(true), do: 1.0
  defp boolean(false), do: 0.0
  defp map_values({:scalar, value}, fun), do: {:scalar, fun.(value)}
  defp map_values({:numbers, frames}, fun), do: {:numbers, Enum.map(frames, &Map.update!(&1, :value, fun))}

  defp map_values({:series, frames}, fun),
    do:
      {:series,
       Enum.map(frames, fn frame -> Map.update!(frame, :points, &Enum.map(&1, fn {t, v} -> {t, fun.(v)} end)) end)}

  defp math({:literal, value}, _, budget) do
    with {:ok, budget} <- charge(budget, 1, 1), do: {:ok, {:scalar, value}, 0, budget}
  end

  defp math({:ref, ref}, results, budget), do: {:ok, results[ref], 0, budget}

  defp math({:unary, op, ast}, results, budget) do
    with {:ok, frames, dropped, budget} <- math(ast, results, budget),
         {:ok, budget} <- charge(budget, point_count(frames), point_count(frames)),
         do: {:ok, map_values(frames, &unary(op, &1)), dropped, budget}
  end

  defp math({:binary, op, left, right}, results, budget) do
    with {:ok, a, dropped_a, budget} <- math(left, results, budget),
         {:ok, b, dropped_b, budget} <- math(right, results, budget),
         {:ok, joined, dropped, budget} <- join(a, b, op, budget),
         do: {:ok, joined, dropped + dropped_a + dropped_b, budget}
  end

  defp unary(_, nil), do: nil
  defp unary(_, :nan), do: :nan
  defp unary("-", value), do: Number.negate(value)
  defp unary("!", value), do: boolean(value == 0)

  defp join({:series, _}, _, _, _), do: {:error, :unsupported_series_math}
  defp join(_, {:series, _}, _, _), do: {:error, :unsupported_series_math}

  defp join({:numbers, []}, _, _, budget), do: {:ok, {:numbers, []}, 0, budget}
  defp join(_, {:numbers, []}, _, budget), do: {:ok, {:numbers, []}, 0, budget}

  defp join({:scalar, a}, {:scalar, b}, op, budget) do
    with {:ok, budget} <- charge(budget, 1, 1), do: {:ok, {:scalar, binary(op, a, b)}, 0, budget}
  end

  defp join(a, b, op, budget) do
    a = numbers(a)
    b = numbers(b)

    with {:ok, budget} <- charge(budget, length(a) * length(b), 0),
         {:ok, values, matched_a, matched_b, budget} <- unions(a, b, op, budget) do
      dropped = length(a) + length(b) - MapSet.size(matched_a) - MapSet.size(matched_b)
      fallback(values, a, b, op, dropped, budget)
    end
  end

  defp numbers({:scalar, value}), do: [%{labels: %{}, value: value}]
  defp numbers({:numbers, frames}), do: frames

  defp unions(a, b, op, budget) do
    indexed = Enum.with_index(b)

    Enum.reduce_while(
      Enum.with_index(a),
      {:ok, [], MapSet.new(), MapSet.new(), budget},
      &union_row(&1, &2, indexed, op)
    )
  end

  defp union_row({x, i}, state, b, op) do
    case Enum.reduce_while(b, state, &union_pair(&1, &2, x, i, op)) do
      {:ok, _, _, _, _} = next -> {:cont, next}
      error -> {:halt, error}
    end
  end

  defp union_pair({y, j}, {:ok, values, ma, mb, budget}, x, i, op) do
    case charge(budget, 0, 0) do
      {:ok, budget} -> union_value(union_labels(x.labels, y.labels), {x, i}, {y, j}, op, {:ok, values, ma, mb, budget})
      error -> {:halt, error}
    end
  end

  defp union_value(nil, _, _, _, state), do: {:cont, state}

  defp union_value(labels, {x, i}, {y, j}, op, {:ok, values, ma, mb, budget}) do
    case charge(budget, 0, 1) do
      {:ok, budget} ->
        {:cont,
         {:ok, [%{labels: labels, value: binary(op, x.value, y.value)} | values], MapSet.put(ma, i), MapSet.put(mb, j),
          budget}}

      error ->
        {:halt, error}
    end
  end

  defp union_labels(a, b) do
    cond do
      a == b -> a
      subset?(a, b) -> b
      subset?(b, a) -> a
      true -> nil
    end
  end

  defp subset?(a, b), do: Enum.all?(a, fn {k, v} -> Map.get(b, k) == v end)

  defp fallback([], [a], [b], op, dropped, budget) do
    with {:ok, budget} <- charge(budget, 0, 1),
         do: {:ok, {:numbers, [%{labels: %{}, value: binary(op, a.value, b.value)}]}, dropped, budget}
  end

  defp fallback(values, _, _, _, dropped, budget), do: {:ok, {:numbers, Enum.reverse(values)}, dropped, budget}

  defp binary(_, nil, _), do: nil
  defp binary(_, _, nil), do: nil
  # Grafana's value-level short circuit precedes NaN propagation. Inputs still
  # execute fully: a missing source never becomes successful false/empty data.
  defp binary("||", a, _) when a != 0, do: 1.0
  defp binary("&&", a, _) when a == 0, do: 0.0
  defp binary(_, :nan, _), do: :nan
  defp binary(_, _, :nan), do: :nan
  defp binary("||", a, b), do: boolean(a != 0 or b != 0)
  defp binary("&&", a, b), do: boolean(a != 0 and b != 0)
  defp binary(op, a, b) when op in ["==", "!=", "<", ">", "<=", ">="], do: boolean(Number.compare(op, a, b))
  defp binary("**", a, b), do: Number.binary("^", a, b)
  defp binary(op, a, b), do: Number.binary(op, a, b)

  defp charge(budget, work, points) do
    cond do
      System.monotonic_time(:millisecond) >= budget.deadline -> {:error, :expression_timeout}
      budget.work + work > @max_work or budget.points + points > @max_points -> {:error, :expression_work_limit}
      true -> {:ok, %{budget | work: budget.work + work, points: budget.points + points}}
    end
  end
end
