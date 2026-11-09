defmodule Pulse.Traces.SearchExpression.Evaluator do
  @moduledoc false
  alias Pulse.Codec.NIF
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.TempoDuration

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
          links: Enum.any?(program, &link?/1),
          instrumentation: Enum.any?(program, &instrumentation?/1),
          trace_duration: SearchExpression.trace_duration?(program),
          context: SearchExpression.context?(program),
          size: length(program)
        }}}
    end
  end

  defp event?({"select", "event", _, _}), do: true
  defp event?({"select", "intrinsic", "event:" <> _, _}), do: true
  defp event?({scope, "event:" <> _, _, _}) when scope in ["intrinsic", "intrinsic.string"], do: true
  defp event?({scope, _, _, _}), do: String.starts_with?(scope, "event.")
  defp link?({"select", "link", _, _}), do: true
  defp link?({"select", "intrinsic", "link:" <> _, _}), do: true
  defp link?({"intrinsic.string", "link:" <> _, _, _}), do: true
  defp link?({scope, _, _, _}), do: String.starts_with?(scope, "link.")
  defp instrumentation?({"select", "instrumentation", _, _}), do: true
  defp instrumentation?({"select", "intrinsic", "instrumentation:" <> _, _}), do: true
  defp instrumentation?({"intrinsic.string", "instrumentation:" <> _, _, _}), do: true
  defp instrumentation?({scope, _, _, _}), do: String.starts_with?(scope, "instrumentation.")

  defp prepare_leaf({scope, key, op, value}) when op in ["=~", "!~"] do
    {:ok, regex} = NIF.compile_log_regex(Pulse.QueryRegex.anchor(value))
    {scope, key, op, regex}
  end

  defp prepare_leaf({scope, key, op, value})
       when scope in [
              "resource.int",
              "span.int",
              "none.int",
              "event.int",
              "link.int",
              "instrumentation.int",
              "intrinsic"
            ], do: {scope, key, op, String.to_integer(value)}

  defp prepare_leaf({scope, key, op, value})
       when scope in [
              "resource.float",
              "span.float",
              "none.float",
              "event.float",
              "link.float",
              "instrumentation.float"
            ], do: {scope, key, op, elem(Float.parse(value), 0)}

  defp prepare_leaf({scope, key, op, value})
       when scope in ["resource.bool", "span.bool", "none.bool", "event.bool", "link.bool", "instrumentation.bool"],
       do: {scope, key, op, value == "true"}

  defp prepare_leaf(leaf), do: leaf

  def structural?(%{relations: relations}), do: relations != []

  @doc "Attach complete retained context before final evaluation; absence is candidate-only."
  def with_context(compiled, context), do: Map.put(compiled, :trace_context, context)

  @doc "Bounded complete-trace context for search/discovery. Input rows must have validated original metadata."
  def trace_context(spans, work \\ 0, root_mode \\ :search) do
    with true <- length(spans) <= 1_000_000,
         {:ok, contexts, work, _} <-
           Enum.reduce_while(spans, {:ok, %{}, work, 0}, &context_span(&1, &2, root_mode)) do
      {:ok, contexts, work}
    else
      false -> {:error, :query_scan_limit}
      error -> error
    end
  end

  defp context_span(span, {:ok, contexts, work, bytes}, root_mode) do
    work = context_work(span.otlp, work)
    previous = Map.get(contexts, span.trace_id)

    context =
      previous ||
        %{
          start: span.timestamp_ns,
          finish: span.end_timestamp_ns,
          root: nil,
          root_id: nil,
          root_conflict: false,
          root_service_known: false
        }

    context = %{
      context
      | start: min(context.start, span.timestamp_ns),
        finish: max(context.finish, span.end_timestamp_ns)
    }

    root? = span.parent_span_id == nil and not child_link?(span, root_mode)
    context = context_root(context, span, root?)
    bytes = bytes + context_bytes(previous, context, span.trace_id, root?)

    cond do
      is_nil(span.otlp) -> {:halt, {:error, :trace_metadata_unknown}}
      map_size(contexts) >= 65_536 and previous == nil -> {:halt, {:error, :trace_group_limit}}
      work > 20_000_000 or bytes > 16_777_216 -> {:halt, {:error, :query_resource_limit}}
      true -> {:cont, {:ok, Map.put(contexts, span.trace_id, context), work, bytes}}
    end
  end

  defp context_work(metadata, work) do
    metadata = metadata || %{}
    work = work + 2 + length(metadata["resource"] || [])
    Enum.reduce(metadata["links"] || [], work, &(&2 + 1 + length(&1)))
  end

  defp context_root(context, _span, false), do: context

  defp context_root(context, span, true) do
    root = {resource_service(span), span.name}
    known = resource_service_known?(span)

    if context.root_id == nil do
      %{context | root: root, root_id: span.span_id, root_service_known: known}
    else
      conflict? = context.root_id != span.span_id or context.root != root

      %{
        context
        | root_conflict: context.root_conflict or conflict?,
          root_service_known: context.root_service_known and known
      }
    end
  end

  defp context_bytes(previous, context, trace_id, root?) do
    base = if previous, do: 0, else: 96 + byte_size(trace_id)

    if root? and context.root != (previous || %{})[:root] do
      base + byte_size(elem(context.root, 0)) + byte_size(elem(context.root, 1))
    else
      base
    end
  end

  defp resource_service(%{otlp: nil}), do: ""

  defp resource_service(span),
    do:
      Enum.find_value(span.otlp["resource"], "", fn
        %{"key" => "service.name", "value" => %{"stringValue" => value}} -> value
        _ -> nil
      end)

  defp resource_service_known?(%{otlp: nil}), do: false

  defp resource_service_known?(span),
    do: Enum.any?(span.otlp["resource"], &match?(%{"key" => "service.name", "value" => %{"stringValue" => _}}, &1))

  def child_link?(span, root_mode \\ :search)

  def child_link?(%{otlp: nil}, _root_mode), do: false

  def child_link?(span, root_mode) do
    Enum.zip(span.links, span.otlp["links"])
    |> Enum.any?(fn {link, attrs} ->
      (root_mode == :discovery or link["trace_id"] == span.trace_id) and
        Enum.any?(attrs, &(&1 == %{"key" => "opentracing.ref_type", "value" => %{"stringValue" => "child_of"}}))
    end)
  end

  @doc "Whether the last spanset matches, with its sampled and selected attributes."
  def evaluate(span, compiled, work) do
    with {:ok, matched, _mask, attributes, work} <- evaluate_mask(span, compiled, work),
         do: {:ok, matched, attributes, work}
  end

  @doc "As `evaluate/3`, plus a bitmask of the spansets that match the span."
  def evaluate_mask(span, compiled, work) do
    resource = Map.new(span.otlp["resource"], &{&1["key"], &1["value"]})
    attrs = Map.new(span.otlp["attributes"], &{&1["key"], &1["value"]})

    events = if compiled.events, do: repeated(span, "events"), else: []
    links = if compiled.links, do: repeated(span, "links"), else: []
    instrumentation = if compiled.instrumentation, do: Map.new(span.otlp["scope"], &{&1["key"], &1["value"]}), else: %{}

    work = work + 2 + map_size(resource) + map_size(attrs) + compiled.size
    work = Enum.reduce(events ++ links, work, &(&2 + 1 + map_size(&1.attrs)))
    work = work + if(compiled.instrumentation, do: 1 + map_size(instrumentation), else: 0)
    work = work + (length(events) + length(links)) * compiled.size * (2 * compiled.size + 8)

    with :ok <- context_status(compiled),
         true <- work <= 20_000_000 do
      context = Map.get(compiled, :trace_context)
      duration = if context, do: context.finish - context.start, else: Map.get(compiled, :duration)

      owners = %{
        resource: resource,
        attrs: attrs,
        events: events,
        links: links,
        instrumentation: instrumentation,
        context: context,
        duration: duration,
        parquet_ids: Map.get(compiled, :parquet_ids, false)
      }

      last = length(compiled.spansets) - 1
      {mask, selected} = spansets(compiled.spansets, last, span, owners)
      owners = scoped_owners(Enum.at(compiled.spansets, last), owners, span)
      selected = Enum.reduce(compiled.select, selected, &select_into(&1, &2, span, owners))
      {:ok, Bitwise.band(mask, Bitwise.bsl(1, last)) != 0, mask, selected, work}
    else
      false -> {:error, :query_resource_limit}
      error -> error
    end
  end

  defp context_status(compiled) do
    context = Map.get(compiled, :trace_context)

    keys =
      for program <- compiled.spansets,
          {"intrinsic.string", key, _, _} <- program,
          key in ~w(rootName rootServiceName),
          do: key

    cond do
      is_nil(context) or keys == [] ->
        :ok

      Map.get(context, :root_conflict, false) ->
        {:error, :trace_root_conflict}

      "rootServiceName" in keys and context.root != nil and not Map.get(context, :root_service_known, false) ->
        {:error, :trace_root_unknown}

      true ->
        :ok
    end
  end

  defp repeated(span, key) do
    metadata = if key == "events", do: span.events, else: span.links

    Enum.zip(metadata, span.otlp[key])
    |> Enum.map(fn {metadata, attrs} -> %{metadata: metadata, attrs: Map.new(attrs, &{&1["key"], &1["value"]})} end)
  end

  defp repeated_scope({scope, key, _, _}) do
    cond do
      String.starts_with?(scope, "event.") or
          (String.starts_with?(scope, "intrinsic") and String.starts_with?(key, "event:")) ->
        :events

      String.starts_with?(scope, "link.") or (scope == "intrinsic.string" and String.starts_with?(key, "link:")) ->
        :links

      true ->
        nil
    end
  end

  # Parquet pushes conjunctions into a single repeated owner. A matching
  # name on event A and matching time on event B is not an AND match.
  defp scoped_owners(program, owners, span) do
    conjunction? = not Enum.any?(program, &match?({"boolean", "", "||", ""}, &1))

    Enum.reduce([:events, :links], owners, fn scope, owners ->
      leaves = Enum.filter(program, &(repeated_scope(&1) == scope))
      filtered = matching_owners(owners[scope], leaves, span, conjunction?)
      Map.put(owners, scope, filtered)
    end)
  end

  defp matching_owners(owners, [], _span, _conjunction?), do: owners

  defp matching_owners(owners, leaves, span, conjunction?) do
    Enum.filter(owners, fn owner ->
      matches = Enum.map(leaves, &repeated_match(&1, owner, span))
      if conjunction?, do: Enum.all?(matches), else: Enum.any?(matches)
    end)
  end

  defp repeated_match({scope, key, op, wanted}, owner, span) do
    {actual, _value} = repeated_value(scope, key, owner, span)
    match_value(actual, op, wanted)
  end

  # The mask of matching spansets and the last spanset's sampled values.
  defp spansets(spansets, last, span, owners) do
    spansets
    |> Enum.with_index()
    |> Enum.reduce({0, %{}}, fn {program, i}, {mask, selected} ->
      owners = scoped_owners(program, owners, span)
      owners = Map.put(owners, :conjunction, not Enum.any?(program, &match?({"boolean", "", "||", ""}, &1)))
      owners = Map.put(owners, :program, program)
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

  defp select(scope, key, _, owners) when scope in ["event", "link"] do
    repeated = if scope == "event", do: owners.events, else: owners.links
    owned(scope, Enum.find_value(Enum.reverse(repeated), & &1.attrs[key]))
  end

  defp select("instrumentation", key, _, owners), do: owned("instrumentation", owners.instrumentation[key])
  defp select("intrinsic", "name", span, _), do: {"intrinsic", %{"stringValue" => span.name}}
  defp select("intrinsic", "status", span, _), do: {"intrinsic", %{"stringValue" => status(span)}}

  defp select("intrinsic", "kind", span, _),
    do: {"intrinsic", %{"stringValue" => Enum.at(~w(unspecified internal server client producer consumer), span.kind)}}

  defp select("intrinsic", key, _span, _owners)
       when key in ~w(duration trace_duration rootName rootServiceName trace:id span:id), do: nil

  defp select("intrinsic", key, span, owners) do
    scope =
      cond do
        String.starts_with?(key, "event:") -> :events
        String.starts_with?(key, "link:") -> :links
        true -> nil
      end

    if scope do
      owner = List.last(owners[scope]) || %{metadata: %{}, attrs: %{}}

      {_actual, value} =
        repeated_value(if(key == "event:timeSinceStart", do: "intrinsic", else: "intrinsic.string"), key, owner, span)

      owned("intrinsic", value)
    else
      {_actual, value, owner} = actual("intrinsic.string", key, span, owners)
      owned(owner, value)
    end
  end

  defp owned(_owner, nil), do: nil
  defp owned(owner, value), do: {owner, value}
  defp status(span), do: Enum.at(~w(unset ok error), span.status["code"])

  defp instruction({"boolean", "", op, ""}, {[rhs, lhs | tail], selected}, _, _),
    do: {[if(op == "&&", do: lhs and rhs, else: lhs or rhs) | tail], selected}

  defp instruction({"constant", "", "true", ""}, {stack, selected}, _, _), do: {[true | stack], selected}

  # Candidate discovery substitutes true for the unknown trace-wide leaf.
  # AND/OR are monotone; final matching runs only with complete retained bounds.
  defp instruction({"intrinsic", "trace_duration", op, wanted}, {stack, selected}, _, owners) do
    matched = is_nil(owners.duration) or match_value({:int, owners.duration}, op, wanted)
    {[matched | stack], selected}
  end

  # Parquet filters individual requested values, then the engine reads the
  # first fetched value per field while AllAttributes samples the last one.
  defp instruction({scope, key, op, wanted} = leaf, {stack, selected}, span, owners)
       when scope in [
              "event.string",
              "event.int",
              "event.float",
              "event.bool",
              "link.string",
              "link.int",
              "link.float",
              "link.bool"
            ] or
              (scope in ["intrinsic", "intrinsic.string"] and
                 key in ["event:name", "event:timeSinceStart", "link:traceID", "link:spanID"]) do
    fetched = fetched_repeated(leaf, owners, span)

    actual =
      case fetched do
        [first | _] -> elem(repeated_value(scope, key, first, span), 0)
        [] -> nil
      end

    value =
      case List.last(fetched) do
        nil -> nil
        last -> elem(repeated_value(scope, key, last, span), 1)
      end

    owner = if String.starts_with?(scope, "intrinsic"), do: "intrinsic", else: hd(String.split(scope, "."))
    selected = if value, do: Map.put(selected, {key, owner}, value), else: selected
    {[match_value(actual, op, wanted) | stack], selected}
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
        if value != nil and match_value(actual, op, wanted), do: Map.put(acc, {key, owner}, value), else: acc
      end)

    {[matched | stack], selected}
  end

  defp instruction({scope, key, op, wanted}, {stack, selected}, span, owners) do
    {actual, value, owner} = actual(scope, key, span, owners)
    wanted = if key == "trace:id", do: String.trim_leading(wanted, "0"), else: wanted
    matched = actual == :unknown or match_value(actual, op, wanted)
    matched = matched and id_pushdown?(key, actual, op, wanted, owners.parquet_ids and owners.conjunction)
    selected = if matched and value != nil, do: Map.put(selected, {key, owner}, value), else: selected
    {[matched | stack], selected}
  end

  defp fetched_repeated({scope, key, _, _} = leaf, owners, span) do
    repeated = if repeated_scope(leaf) == :events, do: owners.events, else: owners.links

    leaves =
      Enum.filter(owners.program, fn {other_scope, other_key, _, _} = other ->
        other_key == key and repeated_scope(other) == repeated_scope(leaf) and
          String.starts_with?(scope, "intrinsic") == String.starts_with?(other_scope, "intrinsic")
      end)

    Enum.filter(repeated, fn owner -> Enum.any?(leaves, &repeated_match(&1, owner, span)) end)
  end

  # Match the pinned Parquet byte predicate as well as its engine's string
  # predicate. Span-ID decoding trims leading zeroes without padding bytes.
  defp id_pushdown?(key, {:string, actual}, op, wanted, true) when key in ["span:id", "span:parentID"] do
    wanted = String.trim_leading(wanted, "0")

    if byte_size(wanted) <= 16 and Regex.match?(~r/\A[0-9a-fA-F]*\z/, wanted) do
      expected = if rem(byte_size(wanted), 2) == 1, do: "0" <> wanted, else: wanted
      actual = if key == "span:parentID" and actual == "0000000000000000", do: "", else: actual
      equal = actual == String.downcase(expected)
      if op == "!=", do: not equal, else: equal
    else
      true
    end
  end

  defp id_pushdown?(_, _, _, _, _), do: true

  defp actual("intrinsic", "duration", span, _),
    do: {{:int, span.end_timestamp_ns - span.timestamp_ns}, nil, "intrinsic"}

  defp actual("intrinsic", "status", span, _),
    do: {{:int, span.status["code"]}, %{"stringValue" => status(span)}, "intrinsic"}

  defp actual("intrinsic", "kind", span, _),
    do:
      {{:int, span.kind},
       %{"stringValue" => Enum.at(~w(unspecified internal server client producer consumer), span.kind)}, "intrinsic"}

  defp actual("intrinsic.string", "name", span, _),
    do: {{:string, span.name}, %{"stringValue" => span.name}, "intrinsic"}

  defp actual("intrinsic.string", key, span, owners) do
    value = intrinsic_value(key, span, owners.context)
    sampled = if key not in ~w(rootName rootServiceName span:id trace:id), do: %{"stringValue" => value}
    {if(value == :unknown, do: :unknown, else: {:string, value}), sampled, "intrinsic"}
  end

  defp actual(scope, key, _, owners) do
    [owner, type] = String.split(scope, ".")

    attrs =
      case owner do
        "resource" -> owners.resource
        "instrumentation" -> owners.instrumentation
        _ -> owners.attrs
      end

    value = Map.get(attrs, key)
    {typed(type, value), value, owner}
  end

  defp intrinsic_value("statusMessage", span, _context), do: span.status["message"]
  defp intrinsic_value("span:id", span, _context), do: span.span_id
  defp intrinsic_value("span:parentID", span, _context), do: span.parent_span_id || "0000000000000000"
  defp intrinsic_value("trace:id", span, _context), do: String.trim_leading(span.trace_id, "0")
  defp intrinsic_value("instrumentation:name", span, _context), do: Map.get(span.scope, "name", "")
  defp intrinsic_value("instrumentation:version", span, _context), do: Map.get(span.scope, "version", "")
  defp intrinsic_value(key, _span, nil) when key in ~w(rootName rootServiceName), do: :unknown

  defp intrinsic_value(key, _span, context) when key in ~w(rootName rootServiceName) do
    {service, name} = context.root || {"", ""}
    if key == "rootName", do: name, else: service
  end

  defp repeated_value("intrinsic", "event:timeSinceStart", owner, span) do
    # The Parquet uint64 subtraction is read back as signed duration nanos.
    n = owner.metadata["timestamp_ns"]
    n = if n, do: n - span.timestamp_ns, else: 0
    sample = if n >= 0, do: TempoDuration.format(n), else: "-" <> TempoDuration.format(-n)
    {{:int, n}, %{"stringValue" => sample}}
  end

  defp repeated_value("intrinsic.string", key, owner, _span) do
    value =
      case key do
        "event:name" -> Map.get(owner.metadata, "name", "")
        "link:traceID" -> String.trim_leading(Map.get(owner.metadata, "trace_id", ""), "0")
        "link:spanID" -> Map.get(owner.metadata, "span_id", "0000000000000000")
      end

    {{:string, value}, %{"stringValue" => value}}
  end

  defp repeated_value(scope, key, owner, _span) do
    [_, type] = String.split(scope, ".")
    value = owner.attrs[key]
    {typed(type, value), value}
  end

  defp typed("any", value), do: {:any, value != nil}
  defp typed("string", %{"stringValue" => text}), do: {:string, text}
  defp typed("int", %{"intValue" => number}), do: {:int, String.to_integer(number)}
  defp typed("bool", %{"boolValue" => value}), do: {:bool, value}
  defp typed("float", %{"doubleValue" => value}), do: {:float, value}
  defp typed(_, _), do: nil

  # BEAM cannot represent IEEE nonfinite floats. The envelope keeps their
  # canonical strings; finite query operands compare with IEEE semantics.
  defp match_value({:any, present?}, op, "nil"), do: present? == (op == "!=")
  defp match_value({:float, "NaN"}, op, _), do: op == "!="
  defp match_value({:float, "Infinity"}, op, _), do: op in ["!=", ">", ">="]
  defp match_value({:float, "-Infinity"}, op, _), do: op in ["!=", "<", "<="]

  defp match_value({:string, value}, op, wanted) when op in ["=~", "!~"] do
    positive = NIF.match_log_regex(wanted, value)
    if op == "!~", do: not positive, else: positive
  end

  defp match_value({_, actual}, "=", wanted), do: actual == wanted
  defp match_value({_, actual}, "!=", wanted), do: actual != wanted
  defp match_value({type, actual}, "<", wanted) when type in [:int, :float], do: actual < wanted
  defp match_value({type, actual}, "<=", wanted) when type in [:int, :float], do: actual <= wanted
  defp match_value({type, actual}, ">", wanted) when type in [:int, :float], do: actual > wanted
  defp match_value({type, actual}, ">=", wanted) when type in [:int, :float], do: actual >= wanted
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
