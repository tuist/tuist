defmodule Pulse.Loki.Detected do
  @moduledoc """
  Loki's detected labels and detected fields, which Grafana's Loki query
  builder and Logs Drilldown use for suggestions.

  Detected fields sample the newest `line_limit` lines a log query selects,
  as Loki does, through the same bounded top-k read as a limited log query.
  Each sampled line contributes its structured metadata (log attributes),
  the labels the query's own parsers extracted, and the fields of its line
  parsed as JSON (nested objects joined with `_`, with their JSON path) or,
  failing that, as logfmt. Parsed names are sanitized as Loki sanitizes them
  and get an `_extracted` suffix when they collide with a stream label.
  Types follow `Pulse.Loki.FieldType`; the type of a field is that of its
  value on the last sampled line. Cardinality is the exact distinct count
  within the sample, where Loki estimates it.

  Detected labels are the stream labels complete discovery returns for the
  selector, with their exact cardinality, omitting labels whose values are
  all numbers or UUIDs unless they are `cluster`, `namespace`, `instance` or
  `pod`, or their nonempty value set consists only of literal `0` and/or `1`.
  """

  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Entry
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Pipeline.Logfmt
  alias Pulse.Loki.Discovery
  alias Pulse.Loki.FieldType
  alias Pulse.Record.Log

  @static_labels ~w(cluster namespace instance pod)
  @error_labels ~w(__error__ __error_details__ __preserve_error__)
  @byte_units ~w(b kib kb mib mb gib gb tib tb pib pb eib eb ki k mi m gi g ti t pi p ei e)

  @type window :: %{start_ns: integer(), end_ns: integer()}

  @doc "Detected fields: `{:ok, [%{label, type, cardinality, parsers, json_path}]}`, at most `limit` of them."
  @spec fields(String.t(), AST.LogQuery.t(), window(), pos_integer(), pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def fields(tenant, query, window, line_limit, limit) do
    with {:ok, lines} <- sample(tenant, query, window, line_limit) do
      {_count, fields} = Enum.reduce(lines, {0, %{}}, &add_line(&1, &2, limit))

      fields
      |> Enum.map(fn {name, field} ->
        %{
          label: name,
          type: field.type,
          cardinality: MapSet.size(field.values),
          parsers: if(field.parsers != [], do: field.parsers),
          json_path: field.json_path
        }
      end)
      |> Enum.sort_by(& &1.label)
      |> then(&{:ok, &1})
    end
  end

  @doc "Distinct values of detected field `name` in the sample, as Loki returns them."
  @spec values(String.t(), AST.LogQuery.t(), String.t(), window(), pos_integer(), pos_integer()) ::
          {:ok, [String.t()]} | {:error, term()}
  def values(tenant, query, name, window, line_limit, limit) do
    with {:ok, lines} <- sample(tenant, query, window, line_limit) do
      lines
      |> Enum.reduce_while(MapSet.new(), &collect_value(&1, &2, name, limit))
      |> Enum.sort()
      |> then(&{:ok, &1})
    end
  end

  defp collect_value(line, acc, name, limit) do
    if MapSet.size(acc) >= limit,
      do: {:halt, acc},
      else: {:cont, acc |> add_values(Map.get(line.metadata, name)) |> add_parsed_values(Map.get(line.parsed, name))}
  end

  @doc "Detected labels: `{:ok, [%{label, cardinality}]}` for the streams `selectors` match."
  @spec labels(String.t(), [AST.Selector.t()], window()) :: {:ok, [map()]} | {:error, term()}
  def labels(tenant, selectors, window) do
    with {:ok, json} <- Discovery.query(tenant, :series, "", selectors, window) do
      json
      |> IO.iodata_to_binary()
      |> Pulse.JSON.decode!()
      |> Enum.reduce(%{}, &add_series/2)
      |> Enum.filter(fn {name, values} ->
        name in @static_labels or numeric_booleans?(values) or not Enum.all?(values, &id_like?/1)
      end)
      |> Enum.map(fn {name, values} -> %{label: name, cardinality: MapSet.size(values)} end)
      |> Enum.sort_by(& &1.label)
      |> then(&{:ok, &1})
    end
  end

  defp add_series(series, acc),
    do:
      Enum.reduce(series, acc, fn {name, value}, acc ->
        Map.update(acc, name, MapSet.new([value]), &MapSet.put(&1, value))
      end)

  # Label suggestions exempt literal numeric booleans, not every numeric
  # spelling of zero/one. FieldType's integer-first classification is separate.
  defp numeric_booleans?(values), do: MapSet.size(values) in 1..2 and Enum.all?(values, &(&1 in ["0", "1"]))

  # -- sampling ---------------------------------------------------------------

  defp sample(tenant, query, window, line_limit) do
    opts =
      Map.merge(Map.take(window, [:timeout_ms]), %{
        start_ts_ns: window.start_ns,
        end_ts_ns: window.end_ns,
        limit: line_limit,
        direction: :backward
      })

    Evaluator.select_entries(query, tenant, opts, &sample_input/2, fn {entry, record} -> observe(entry, record) end)
  end

  # Retain only observation inputs, not original OTLP envelopes or duplicate
  # bodies. Parse lines after global top-k, not on every transient candidate.
  defp sample_input(entry, record) do
    {entry,
     %Log{
       service: record.service,
       severity_text: record.severity_text,
       resource: record.resource,
       attributes: record.attributes
     }}
  end

  # What one line contributes: structured metadata, and parsed fields with the
  # parser that produced them and their JSON paths.
  defp observe(%Entry{} = entry, %Log{} = record) do
    base = Entry.from_record(record).labels
    stream = Entry.from_record(%{record | attributes: %{}}).labels
    metadata = Map.take(base, Map.keys(record.attributes || %{}) |> Enum.map(&to_string/1))

    query_parsed =
      entry.labels
      |> Map.drop(Map.keys(base))
      |> Map.drop(@error_labels)
      |> Map.new(fn {name, value} -> {name, [value]} end)

    {parser, line_parsed, paths} = parse_line(entry.line, Map.drop(stream, Map.keys(query_parsed)))
    parsed = Map.merge(query_parsed, line_parsed, fn _name, a, b -> Enum.uniq(a ++ b) end)

    %{metadata: metadata, parsed: parsed, parsers: [parser], json_paths: paths}
  end

  defp parse_line(line, stream) do
    case json_fields(line, stream) do
      {:ok, fields, paths} -> {"json", fields, paths}
      :error -> {"logfmt", logfmt_fields(line, stream), %{}}
    end
  end

  defp json_fields(line, stream) do
    case decode_detected_json(line) do
      {:ok, %{} = object} ->
        {fields, paths} = flatten(object, [], stream, {%{}, %{}})
        {:ok, Map.new(fields, fn {name, value} -> {name, [value]} end), paths}

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  # Loki's detector uses jsonparser.ObjectEach, which accepts a comma after
  # the final object value. Keep this compatibility local to sampled lines:
  # ordinary JSON transport and pipeline parsers must remain unchanged.
  defp decode_detected_json(line) do
    case Pulse.JSON.decode(line) do
      {:ok, _} = result -> result
      _ -> decode_object_commas(line, object_commas(line, nil, [], byte_size(line)))
    end
  end

  # Only record candidate commas outside complete strings. A preceding value
  # must end in a quote, container close, digit, true/false's e or null's l.
  # Strict decoding AFTER deletion still proves the entire object structure
  # and every value. Leading/doubled/missing-value commas cannot disappear;
  # array-terminal commas never qualify. No other bytes change.
  defp object_commas(<<>>, _previous, offsets, _size), do: Enum.reverse(offsets)

  defp object_commas(<<?", rest::binary>>, _previous, offsets, size) do
    case after_json_string(rest) do
      {:ok, rest} -> object_commas(rest, ?", offsets, size)
      :error -> []
    end
  end

  defp object_commas(<<?,, rest::binary>> = source, previous, offsets, size) do
    candidate? = previous in [?", ?}, ?], ?e, ?l] or previous in ?0..?9

    offsets =
      if candidate? and match?(<<?}, _::binary>>, json_space(rest)),
        do: [size - byte_size(source) | offsets],
        else: offsets

    object_commas(rest, ?,, offsets, size)
  end

  defp object_commas(<<char, rest::binary>>, previous, offsets, size) when char in [32, 9, 10, 13],
    do: object_commas(rest, previous, offsets, size)

  defp object_commas(<<char, rest::binary>>, _previous, offsets, size), do: object_commas(rest, char, offsets, size)

  defp after_json_string(<<?\\, _escaped, rest::binary>>), do: after_json_string(rest)
  defp after_json_string(<<?", rest::binary>>), do: {:ok, rest}
  defp after_json_string(<<_char, rest::binary>>), do: after_json_string(rest)
  defp after_json_string(<<>>), do: :error

  defp json_space(<<char, rest::binary>>) when char in [32, 9, 10, 13], do: json_space(rest)
  defp json_space(source), do: source

  defp decode_object_commas(_line, []), do: :error

  # Traversal and lookahead visit each byte at most twice. Offsets/chunks grow
  # only with removed commas; disjoint original slices are copied once into a
  # binary strictly smaller than the selected line. Never copy growing prefixes.
  defp decode_object_commas(line, offsets) do
    {chunks, start} =
      Enum.reduce(offsets, {[], 0}, fn offset, {chunks, start} ->
        {[binary_part(line, start, offset - start) | chunks], offset + 1}
      end)

    tail = binary_part(line, start, byte_size(line) - start)
    repaired = [tail | chunks] |> Enum.reverse() |> IO.iodata_to_binary()
    Pulse.JSON.decode(repaired)
  end

  # Strings, numbers and booleans become fields; objects nest with `_`;
  # arrays and nulls are skipped, as Loki's JSON parser does.
  defp flatten(object, path, stream, acc) do
    Enum.reduce(object, acc, fn {key, value}, {fields, paths} = acc ->
      key_path = path ++ [key]

      case value do
        %{} -> flatten(value, key_path, stream, acc)
        v when is_binary(v) or is_number(v) or is_boolean(v) -> put_field(key_path, json_text(v), stream, fields, paths)
        _ -> acc
      end
    end)
  end

  defp put_field(key_path, value, stream, fields, paths) do
    name = key_path |> Enum.map(&sanitize(&1, false)) |> Enum.reject(&(&1 == "")) |> Enum.join("_")
    name = if(Regex.match?(~r/\A[0-9]/, name), do: "_" <> name, else: name)
    name = if Map.has_key?(stream, name), do: name <> "_extracted", else: name
    {Map.put(fields, name, value), Map.put(paths, name, key_path)}
  end

  defp json_text(v) when is_binary(v), do: String.replace(v, "�", " ")
  defp json_text(true), do: "true"
  defp json_text(false), do: "false"
  defp json_text(v) when is_integer(v), do: Integer.to_string(v)
  defp json_text(v) when is_float(v), do: Pulse.JSON.encode!(v)

  defp logfmt_fields(line, stream) do
    line
    |> Logfmt.parse(false)
    |> Enum.map(fn {key, value} -> {sanitize(key, true), value} end)
    |> Enum.reject(&(elem(&1, 0) == ""))
    |> Enum.reduce(%{}, fn {name, value}, fields ->
      name = if Map.has_key?(stream, name), do: name <> "_extracted", else: name
      # The decoder already skipped empty values. First retained extraction
      # owns the final destination, including normalized and suffix collisions.
      Map.put_new(fields, name, [value])
    end)
  end

  # Loki's sanitizeLabelKey.
  defp sanitize(key, prefix?) do
    key = String.trim(key)
    key = if prefix? and Regex.match?(~r/\A[0-9]/, key), do: "_" <> key, else: key
    String.replace(key, ~r/[^a-zA-Z0-9_]/u, "_")
  end

  # -- accumulation -------------------------------------------------------------

  defp add_line(line, acc, limit) do
    acc =
      Enum.reduce(line.metadata, acc, fn {name, value}, acc ->
        update_field(acc, name, [value], [], nil, limit)
      end)

    Enum.reduce(line.parsed, acc, fn {name, values}, acc ->
      path = if "json" in line.parsers, do: Map.get(line.json_paths, name)
      update_field(acc, name, values, line.parsers, {:path, path}, limit)
    end)
  end

  defp update_field({count, fields} = acc, name, values, parsers, path, limit) do
    case Map.fetch(fields, name) do
      {:ok, field} ->
        {count, Map.put(fields, name, observe_values(field, values, parsers, path))}

      :error when count < limit ->
        field = %{type: "string", values: MapSet.new(), parsers: parsers, json_path: nil}
        {count + 1, Map.put(fields, name, observe_values(field, values, parsers, path))}

      :error ->
        acc
    end
  end

  defp observe_values(field, [first | _] = values, parsers, path) do
    json_path =
      case path do
        {:path, path} -> path
        nil -> field.json_path
      end

    %{
      field
      | type: FieldType.detect(first),
        values: Enum.into(values, field.values),
        parsers: Enum.uniq(field.parsers ++ parsers),
        json_path: json_path
    }
  end

  defp add_values(set, nil), do: set
  defp add_values(set, value), do: MapSet.put(set, value)

  defp add_parsed_values(set, nil), do: set

  # Byte sizes are normalized so they can go straight into a query.
  defp add_parsed_values(set, values) do
    Enum.reduce(values, set, fn value, set ->
      with true <- String.ends_with?(String.downcase(value), @byte_units),
           {:ok, bytes} <- FieldType.bytes(value) do
        MapSet.put(set, FieldType.format_bytes(bytes))
      else
        _ -> MapSet.put(set, value)
      end
    end)
  end

  # Go's ParseFloat or google/uuid Parse accept the value.
  defp id_like?(value), do: FieldType.detect(value) in ["int", "float"] or uuid?(value)

  defp uuid?(value) do
    (Regex.match?(
       ~r/\A(urn:uuid:|\{)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}?\z/,
       value
     ) and
       braces_balanced?(value)) or Regex.match?(~r/\A[0-9a-fA-F]{32}\z/, value)
  end

  defp braces_balanced?("{" <> rest), do: String.ends_with?(rest, "}")
  defp braces_balanced?(value), do: not String.ends_with?(value, "}")
end
