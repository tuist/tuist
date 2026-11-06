defmodule Pulse.Traces.TempoFilter do
  @moduledoc false
  alias Pulse.Record.Span
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.SearchExpression.Evaluator

  # Only the already validated, deduplicated complete trace reaches apply/2.
  # A filter never changes storage admission, integrity checks or export bounds.
  def parse(params) do
    case Map.get(params, "q", "") do
      query when is_binary(query) and byte_size(query) <= 16_384 ->
        if String.trim(query) == "", do: {:ok, nil}, else: compile(String.trim(query), params)

      _ ->
        {:error, :unsupported_parameters}
    end
  end

  defp compile(query, params) do
    with {:ok, hierarchy?} <- hierarchy(params["keep_hierarchy"]),
         {:ok, descendants} <- depth(params["match_depth"], 0),
         {:ok, ancestors} <- if(hierarchy?, do: depth(params["ancestor_depth"], -1), else: {:ok, 0}),
         {:ok, program} <- program(query) do
      {:ok, %{program: program, ancestors: ancestors, descendants: descendants}}
    end
  end

  defp program(query) do
    if Regex.match?(~r/\A\{\s*\}\z/u, query) do
      {:ok, nil}
    else
      # Trace-by-ID filters keep or drop single spans: no joins or selection.
      with {:ok, {:expression, program}} <- SearchExpression.parse(query),
           {:ok, {:expression, prepared}} <- Evaluator.prepare(program),
           false <- SearchExpression.scoped?(program),
           false <- Evaluator.structural?(prepared) or prepared.select != [] or prepared.context do
        {:ok, prepared}
      else
        true -> {:error, :unsupported_trace_selector}
        error -> error
      end
    end
  end

  defp hierarchy(value) when value in [nil, "", "0", "f", "F", "false", "False", "FALSE"], do: {:ok, false}
  defp hierarchy(value) when value in ["1", "t", "T", "true", "True", "TRUE"], do: {:ok, true}
  defp hierarchy(_value), do: {:error, :unsupported_parameters}

  defp depth(value, default) when value in [nil, ""], do: {:ok, default}

  defp depth(value, _default) when is_binary(value) and byte_size(value) <= 20 do
    case Integer.parse(value) do
      {n, ""} when n >= -1 and n <= 9_223_372_036_854_775_807 -> {:ok, n}
      _ -> {:error, :unsupported_parameters}
    end
  end

  defp depth(_value, _default), do: {:error, :unsupported_parameters}

  def apply(spans, nil), do: {:ok, spans, false}
  def apply(spans, %{program: nil}), do: {:ok, spans, false}

  def apply(spans, filter) do
    with {:ok, matched} <- matches(spans, filter.program) do
      parents = Map.new(spans, &{&1["span_id"], List.wrap(&1["parent_span_id"])})
      children = Enum.group_by(spans, & &1["parent_span_id"], & &1["span_id"])
      seeds = MapSet.to_list(matched)
      ancestors = walk(seeds, matched, parents, filter.ancestors)
      descendants = walk(seeds, matched, children, filter.descendants)
      kept = MapSet.union(ancestors, descendants)
      selected = Enum.filter(spans, &MapSet.member?(kept, &1["span_id"]))
      {:ok, selected, length(selected) < length(spans)}
    end
  end

  defp matches(spans, program) do
    Enum.reduce_while(spans, {:ok, MapSet.new(), 0}, fn span, {:ok, selected, work} ->
      case Evaluator.evaluate(Span.from_map(span), program, work) do
        {:ok, true, _attributes, work} ->
          {:cont, {:ok, MapSet.put(selected, span["span_id"]), work}}

        {:ok, false, _attributes, work} ->
          {:cont, {:ok, selected, work}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, selected, _work} -> {:ok, selected}
      error -> error
    end
  end

  # Multi-source breadth-first traversal gives every span its shortest distance
  # from any match. Each ID/edge is visited once per direction, including cycles;
  # ancestor and descendant walks both start at matches, never at each other's
  # expanded relatives (which would accidentally include sibling branches).
  defp walk([], seen, _adjacency, _depth), do: seen
  defp walk(_frontier, seen, _adjacency, 0), do: seen

  defp walk(frontier, seen, adjacency, depth) do
    next =
      frontier
      |> Enum.flat_map(&Map.get(adjacency, &1, []))
      |> MapSet.new()
      |> MapSet.difference(seen)

    walk(MapSet.to_list(next), MapSet.union(seen, next), adjacency, if(depth == -1, do: -1, else: depth - 1))
  end
end
