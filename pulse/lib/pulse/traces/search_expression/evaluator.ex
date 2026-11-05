defmodule Pulse.Traces.SearchExpression.Evaluator do
  @moduledoc false
  alias Pulse.Codec.NIF
  alias Pulse.Traces.SearchExpression

  def prepare(program) do
    with :ok <- SearchExpression.validate(program),
         {:ok, {spansets, relations, select}} <- SearchExpression.split(program) do
      {:ok,
       {:expression,
        %{
          spansets: Enum.map(spansets, fn spanset -> Enum.map(spanset, &prepare_leaf/1) end),
          relations: relations,
          select: Enum.map(select, fn {"select", scope, key, ""} -> {scope, key} end),
          events: Enum.any?(program, &event?/1),
          size: length(program)
        }}}
    end
  end

  defp event?({"select", "event", _, _}), do: true
  defp event?({scope, _, _, _}), do: String.starts_with?(scope, "event.")

  defp prepare_leaf({scope, key, op, value}) when op in ["=~", "!~"] do
    {:ok, regex} = NIF.compile_log_regex(Pulse.QueryRegex.anchor(value))
    {scope, key, op, regex}
  end

  defp prepare_leaf({scope, key, op, value})
       when scope in ["resource.int", "span.int", "none.int", "event.int", "intrinsic"],
       do: {scope, key, op, String.to_integer(value)}

  defp prepare_leaf(leaf), do: leaf

  def structural?(%{relations: relations}), do: relations != []

  @doc "Whether the last spanset matches, with its sampled and selected attributes."
  def evaluate(span, compiled, work) do
    with {:ok, matched, _mask, attributes, work} <- evaluate_mask(span, compiled, work),
         do: {:ok, matched, attributes, work}
  end

  @doc "As `evaluate/3`, plus a bitmask of the spansets that match the span."
  def evaluate_mask(span, compiled, work) do
    resource = Map.new(span.otlp["resource"], &{&1["key"], &1["value"]})
    attrs = Map.new(span.otlp["attributes"], &{&1["key"], &1["value"]})

    events =
      if compiled.events, do: Enum.map(span.otlp["events"], &Map.new(&1, fn a -> {a["key"], a["value"]} end)), else: []

    work = work + 2 + map_size(resource) + map_size(attrs) + compiled.size
    work = Enum.reduce(events, work, &(&2 + 1 + map_size(&1)))

    if work > 20_000_000 do
      {:error, :query_resource_limit}
    else
      owners = %{resource: resource, attrs: attrs, events: events}
      last = length(compiled.spansets) - 1
      {mask, selected} = spansets(compiled.spansets, last, span, owners)
      selected = Enum.reduce(compiled.select, selected, &select_into(&1, &2, span, owners))
      attributes = selected |> Enum.sort() |> Enum.map(fn {{key, _}, value} -> %{"key" => key, "value" => value} end)
      {:ok, Bitwise.band(mask, Bitwise.bsl(1, last)) != 0, mask, attributes, work}
    end
  end

  # The mask of matching spansets and the last spanset's sampled values.
  defp spansets(spansets, last, span, owners) do
    spansets
    |> Enum.with_index()
    |> Enum.reduce({0, %{}}, fn {program, i}, {mask, selected} ->
      {[matched], collected} = Enum.reduce(program, {[], %{}}, &instruction(&1, &2, span, owners))
      selected = if i == last, do: collected, else: selected
      {if(matched, do: Bitwise.bor(mask, Bitwise.bsl(1, i)), else: mask), selected}
    end)
  end

  defp select_into({scope, key}, acc, span, owners) do
    case select(scope, key, span, owners) do
      nil -> acc
      {owner, value} -> Map.put_new(acc, {key, owner}, value)
    end
  end

  defp select("resource", key, _, owners), do: owned("resource", owners.resource[key])
  defp select("span", key, _, owners), do: owned("span", owners.attrs[key])

  defp select("none", key, _, owners),
    do:
      if(Map.has_key?(owners.attrs, key),
        do: {"span", owners.attrs[key]},
        else: owned("resource", owners.resource[key])
      )

  defp select("event", key, _, owners), do: owned("event", Enum.find_value(owners.events, & &1[key]))
  defp select("intrinsic", "name", span, _), do: {"intrinsic", %{"stringValue" => span.name}}
  defp select("intrinsic", "status", span, _), do: {"intrinsic", %{"stringValue" => status(span)}}

  defp select("intrinsic", "kind", span, _),
    do: {"intrinsic", %{"stringValue" => Enum.at(~w(unspecified internal server client producer consumer), span.kind)}}

  defp owned(_owner, nil), do: nil
  defp owned(owner, value), do: {owner, value}
  defp status(span), do: Enum.at(~w(unset ok error), span.status["code"])

  defp instruction({"boolean", "", op, ""}, {[rhs, lhs | tail], selected}, _, _),
    do: {[if(op == "&&", do: lhs and rhs, else: lhs or rhs) | tail], selected}

  # Any event with a matching original value, as Tempo's Parquet fetch
  # selects event attributes; the first matching event's value is sampled.
  defp instruction({"event." <> type, key, op, wanted}, {stack, selected}, _span, owners) do
    value =
      Enum.find_value(owners.events, fn event ->
        value = event[key]
        if value && match_value(typed(type, value), op, wanted), do: value
      end)

    selected = if value, do: Map.put(selected, {key, "event"}, value), else: selected
    {[value != nil | stack], selected}
  end

  defp instruction({"none." <> type, key, op, wanted}, {stack, selected}, span, owners) do
    # Presence, not a successful typed comparison, selects the winning owner.
    owner = if Map.has_key?(owners.attrs, key), do: "span", else: "resource"
    {actual, _, _} = actual(owner <> "." <> type, key, span, owners)
    matched = match_value(actual, op, wanted)

    # Tempo samples independently matching values from both requested owners,
    # even when this leaf is false and another OR branch selects the span.
    selected =
      Enum.reduce(["resource", "span"], selected, fn owner, acc ->
        {actual, value, _} = actual(owner <> "." <> type, key, span, owners)
        if match_value(actual, op, wanted), do: Map.put(acc, {key, owner}, value), else: acc
      end)

    {[matched | stack], selected}
  end

  defp instruction({scope, key, op, wanted}, {stack, selected}, span, owners) do
    {actual, value, owner} = actual(scope, key, span, owners)
    matched = match_value(actual, op, wanted)
    selected = if matched and value != nil, do: Map.put(selected, {key, owner}, value), else: selected
    {[matched | stack], selected}
  end

  defp actual("intrinsic", "duration", span, _),
    do: {{:int, span.end_timestamp_ns - span.timestamp_ns}, nil, "intrinsic"}

  defp actual("intrinsic", "status", span, _),
    do: {{:int, span.status["code"]}, %{"stringValue" => status(span)}, "intrinsic"}

  defp actual(scope, key, _, owners) do
    [owner, type] = String.split(scope, ".")
    value = Map.get(if(owner == "resource", do: owners.resource, else: owners.attrs), key)
    {typed(type, value), value, owner}
  end

  defp typed("string", %{"stringValue" => text}), do: {:string, text}
  defp typed("int", %{"intValue" => number}), do: {:int, String.to_integer(number)}
  defp typed(_, _), do: nil

  defp match_value({:string, value}, op, wanted) when op in ["=~", "!~"] do
    positive = NIF.match_log_regex(wanted, value)
    if op == "!~", do: not positive, else: positive
  end

  defp match_value({_, actual}, "=", wanted), do: actual == wanted
  defp match_value({_, actual}, "!=", wanted), do: actual != wanted
  defp match_value({:int, actual}, "<", wanted), do: actual < wanted
  defp match_value({:int, actual}, "<=", wanted), do: actual <= wanted
  defp match_value({:int, actual}, ">", wanted), do: actual > wanted
  defp match_value({:int, actual}, ">=", wanted), do: actual >= wanted
  defp match_value(_, _, _), do: false

  @doc """
  Which of one trace's spans a structural chain returns, given each span as
  `{span_id, parent_span_id, mask}`. Relations follow parent span IDs, so
  duplicate rows of a span share its relatives, a missing parent ends a chain
  and cycles terminate. Mirrors the native `structural`.
  """
  def structural(relations, spans) do
    children = spans |> Enum.reject(&is_nil(elem(&1, 1))) |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    parents = spans |> Enum.reject(&is_nil(elem(&1, 1))) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    current = Enum.map(spans, fn {_, _, mask} -> Bitwise.band(mask, 1) != 0 end)

    relations
    |> Enum.with_index(1)
    |> Enum.reduce(current, fn {relation, i}, current ->
      bit = Bitwise.bsl(1, i)
      chosen = spans |> Enum.zip(current) |> Enum.filter(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
      ids = MapSet.new(chosen, &elem(&1, 0))
      related? = related(relation, chosen, ids, children, parents)
      Enum.map(spans, fn {_, _, mask} = span -> Bitwise.band(mask, bit) != 0 and related?.(span) end)
    end)
  end

  defp related(">", _chosen, ids, _children, _parents), do: fn {_, parent, _} -> MapSet.member?(ids, parent) end

  defp related("<", chosen, _ids, _children, _parents) do
    wanted = MapSet.new(chosen, &elem(&1, 1))
    fn {id, _, _} -> MapSet.member?(wanted, id) end
  end

  defp related(">>", _chosen, ids, children, _parents) do
    down = closure(MapSet.to_list(ids), children)
    fn {_, parent, _} -> parent != nil and MapSet.member?(down, parent) end
  end

  defp related("<<", chosen, _ids, _children, parents) do
    up = chosen |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> closure(parents)
    fn {id, _, _} -> MapSet.member?(up, id) end
  end

  defp related("~", chosen, _ids, _children, _parents) do
    by_parent = chosen |> Enum.reject(&is_nil(elem(&1, 1))) |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    fn {id, parent, _} -> parent != nil and Enum.any?(Map.get(by_parent, parent, []), &(&1 != id)) end
  end

  defp closure(seeds, edges), do: closure(seeds, edges, MapSet.new(seeds))
  defp closure([], _edges, seen), do: seen

  defp closure([id | rest], edges, seen) do
    next = edges |> Map.get(id, []) |> Enum.reject(&MapSet.member?(seen, &1))
    closure(next ++ rest, edges, Enum.into(next, seen))
  end
end
