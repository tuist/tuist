defmodule Pulse.LogQL.Pipeline do
  @moduledoc """
  Pipeline runner: applies an ordered list of LogQL stage ASTs to a
  stream of `Pulse.LogQL.Entry` values.

  Every stage returns `{:keep, entry} | :drop`. The runner short-circuits
  on `:drop` and drops the record from the output stream. Stages have
  no cross-record state — anything they compute is folded into the
  entry's `labels` or `line`.

  Stages that come pre-pushed into the storage layer (selector matchers
  and line filters at the head of the pipeline) are removed by
  `Pulse.LogQL.Evaluator` before this runner sees them, so this module
  runs exactly the stages Rust does not.
  """

  alias Pulse.Codec.NIF
  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Entry
  alias Pulse.LogQL.Pipeline.IP
  alias Pulse.LogQL.Pipeline.Json
  alias Pulse.LogQL.Pipeline.Logfmt
  alias Pulse.LogQL.Pipeline.Pattern
  alias Pulse.LogQL.Pipeline.Template
  alias Pulse.LogQL.Quantity
  alias Pulse.LogQL.StreamMatchers
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number

  @type stage :: struct()
  @type result :: {:keep, Entry.t()} | :drop

  # ---------------------------------------------------------------------------
  # Runner
  # ---------------------------------------------------------------------------

  @doc """
  Compile a list of AST stages into an internal representation, resolving
  regex patterns, pre-parsing templates, etc. Compilation is done once
  per query; the compiled stages then run against every entry.
  """
  @spec compile([stage()]) :: [term()]
  def compile(stages) when is_list(stages) do
    Enum.map(stages, &compile_stage/1)
  end

  @doc false
  # This is query syntax, never a caller-supplied __preserve_error__ label.
  # As in Loki's stage hints, any string filter asking for errored lines
  # covers errors raised both before and after that filter in the pipeline.
  def preserves_errors?(stages) do
    Enum.any?(stages, fn
      %AST.LabelFilter{expr: expr} -> preserves_error_filter?(compile_label_filter(expr))
      _ -> false
    end)
  end

  defp preserves_error_filter?({op, left, right}) when op in [:and, :or],
    do: preserves_error_filter?(left) or preserves_error_filter?(right)

  defp preserves_error_filter?({:cmp, "__error__", op, {type, _} = value})
       when op in [:eq, :neq, :re, :nre] and type in [:string, :re] do
    errors = ~w(JSONParserErr LogfmtParserErr SampleExtractionErr LabelFilterErr TemplateFormatErr)

    not eval_cmp(op, "", value) or Enum.any?(errors, &eval_cmp(op, &1, value))
  end

  defp preserves_error_filter?(_), do: false

  @doc "Apply every compiled stage to a stream of entries."
  @spec run([term()], Enumerable.t(Entry.t())) :: Enumerable.t(Entry.t())
  def run(compiled, entries) do
    entries
    |> Stream.transform(:ok, fn entry, acc ->
      case __MODULE__.apply(compiled, entry) do
        {:keep, e} -> {[e], acc}
        :drop -> {[], acc}
      end
    end)
  end

  @doc "Apply every compiled stage to one entry; stages are stateless."
  @spec apply([term()], Entry.t()) :: result()
  def apply(compiled, %Entry{} = entry),
    do: run_stages(compiled, Entry.initialize_errors(%{entry | base_labels: entry.base_labels || entry.labels}))

  defp run_stages([], entry), do: {:keep, entry}

  defp run_stages([stage | rest], entry) do
    case apply_stage(stage, entry) do
      {:keep, updated} -> run_stages(rest, updated)
      :drop -> :drop
    end
  end

  # ---------------------------------------------------------------------------
  # Stage compilation — done once per query, before the record loop
  # ---------------------------------------------------------------------------

  defp compile_stage(%AST.LineFilter{op: op, value: value}) do
    {:line_filter, op, compile_line_filter_value(value)}
  end

  defp compile_stage(%AST.LabelFilter{expr: expr}) do
    {:label_filter, compile_label_filter(expr)}
  end

  defp compile_stage(%AST.JsonParser{fields: []}), do: {:json, []}

  defp compile_stage(%AST.JsonParser{fields: fields}) do
    paths =
      Enum.map(fields, fn {label, source} ->
        {:ok, path} = Json.expression(source)
        {label, path}
      end)

    {:json, paths}
  end

  defp compile_stage(%AST.LogfmtParser{fields: fields, flags: flags}) do
    fields =
      Enum.map(fields, fn {label, source} ->
        {:ok, key} = Logfmt.expression(source)
        {label, key}
      end)

    fields = Map.new(fields)

    # The pinned Go parser selects one destination through map iteration.
    # Choose one valid owner deterministically when aliases share a source.
    sources = fields |> Enum.sort() |> Enum.reduce(%{}, fn {label, source}, acc -> Map.put_new(acc, source, label) end)
    {:logfmt, fields, sources, :keep_empty in flags, :strict in flags}
  end

  defp compile_stage(%AST.RegexpParser{pattern: pattern}) do
    {:regexp, compile_regex(pattern)}
  end

  defp compile_stage(%AST.PatternParser{pattern: pattern}) do
    {:ok, template} = Pattern.compile_parser(pattern)
    {:pattern, template}
  end

  defp compile_stage(%AST.UnpackParser{}), do: :unpack

  defp compile_stage(%AST.LineFormat{template: t}) do
    {:ok, template} = Template.compile(t)
    # Loki's single-field line formatter uses ordinary Get, unlike template
    # execution's rendered map. Retain rendering/work/output checks here; only
    # select the matching label view for the two independently owned names.
    case Enum.reject(template, &(&1 == {:literal, ""})) do
      [{:action, [[{:field, {:root}, [name]}]]}] when name in ["__error__", "__error_details__"] ->
        {:line_format, template, :ordinary_error_label}

      _ ->
        {:line_format, template}
    end
  end

  defp compile_stage(%AST.LabelFormat{entries: entries}) do
    compiled =
      Enum.map(entries, fn
        {name, {:template, t}} ->
          {:ok, template} = Template.compile(t)
          {name, {:template, template}}

        {name, {:rename, src}} ->
          {name, {:rename, src}}
      end)

    {:label_format, compiled}
  end

  defp compile_stage(%AST.Drop{entries: entries}) do
    {:drop, Enum.map(entries, &compile_drop_entry/1)}
  end

  defp compile_stage(%AST.Keep{entries: entries}) do
    {:keep, Enum.map(entries, &compile_drop_entry/1)}
  end

  defp compile_stage(%AST.Decolorize{}), do: :decolorize

  defp compile_stage(%AST.Unwrap{} = unwrap), do: {:unwrap, unwrap}

  defp compile_line_filter_value({:string, s}), do: {:string, s}
  defp compile_line_filter_value({:re, pat}), do: {:re, compile_regex(pat)}

  defp compile_line_filter_value({:or, values}), do: {:or, Enum.map(values, &compile_line_filter_value/1)}

  defp compile_line_filter_value({:pattern, pattern}) do
    {:ok, parts} = Pattern.compile_filter(pattern)
    {:pattern, parts}
  end

  defp compile_line_filter_value({:ip, pattern}) do
    {:ok, matcher} = IP.compile(pattern)
    {:ip, matcher}
  end

  defp compile_regex(pat) do
    {:ok, re} = NIF.compile_log_regex(pat)
    re
  end

  # Label matchers (filters, drop/keep) match whole values, as in Loki;
  # line filters and the regexp parser stay unanchored searches.
  defp compile_label_regex(pat), do: pat |> StreamMatchers.anchor() |> compile_regex()

  defp compile_drop_entry({name, :any}), do: {name, :any}
  defp compile_drop_entry({name, {:eq, v}}), do: {name, {:eq, v}}
  defp compile_drop_entry({name, {:neq, v}}), do: {name, {:neq, v}}
  defp compile_drop_entry({name, {:re, pat}}), do: {name, {:re, compile_label_regex(pat)}}
  defp compile_drop_entry({name, {:nre, pat}}), do: {name, {:nre, compile_label_regex(pat)}}

  # Label-filter tree: recursively compile so leaf regexes precompile once.
  defp compile_label_filter({:and, l, r}), do: {:and, compile_label_filter(l), compile_label_filter(r)}
  defp compile_label_filter({:or, l, r}), do: {:or, compile_label_filter(l), compile_label_filter(r)}

  defp compile_label_filter({:cmp, name, op, {:re, pat}}) do
    {:cmp, name, op, {:re, compile_label_regex(pat)}}
  end

  defp compile_label_filter({:cmp, name, op, {:ip, pattern}}) do
    {:ok, matcher} = IP.compile(pattern)
    {:cmp, name, op, {:ip, matcher}}
  end

  defp compile_label_filter({:cmp, name, op, value}) do
    {:cmp, name, op, value}
  end

  # ---------------------------------------------------------------------------
  # Stage application
  # ---------------------------------------------------------------------------

  defp apply_stage({:line_filter, op, value}, %Entry{} = e) do
    if line_matches?(op, value, e.line), do: {:keep, e}, else: :drop
  end

  defp apply_stage({:label_filter, tree}, %Entry{} = e) do
    case eval_label_filter(tree, e) do
      {true, entry} -> {:keep, entry}
      {false, _} -> :drop
    end
  end

  defp apply_stage({:json, []}, %Entry{} = e) do
    case decode_json_labels(e.line) do
      {:ok, fields} ->
        {:keep, extract_labels(e, fields)}

      {:error, details} ->
        {:keep, Entry.set_error(e, "JSONParserErr", details)}
    end
  end

  defp apply_stage({:json, _fields}, %Entry{line: ""} = e), do: {:keep, e}

  defp apply_stage({:json, fields}, %Entry{line: <<char, _::binary>>} = e) when char in [?{, ?[, ?"],
    do: {:keep, extract_json_fields(e, fields)}

  defp apply_stage({:json, _fields}, %Entry{} = e), do: {:keep, Entry.set_error(e, "JSONParserErr")}

  defp apply_stage({:logfmt, fields, sources, keep_empty?, strict?}, %Entry{} = e) do
    mode = if map_size(fields) == 0, do: :all, else: :explicit
    {pairs, error} = Logfmt.decode(e.line, strict?, mode)
    pairs = if keep_empty? or mode == :explicit, do: pairs, else: Enum.reject(pairs, &(elem(&1, 1) == ""))
    {e, stopped?} = extract_logfmt_fields(pairs, fields, sources, e)

    e =
      if error && not stopped? do
        Entry.set_error(e, "LogfmtParserErr", error)
      else
        e
      end

    {:keep, e}
  end

  defp apply_stage({:regexp, regex}, %Entry{} = e) do
    captures = NIF.log_regex_named_captures(regex, e.line) || %{}
    {:keep, extract_labels(e, captures)}
  end

  defp apply_stage({:pattern, tmpl}, %Entry{} = e) do
    case Pattern.match(tmpl, e.line) do
      {:ok, caps} -> {:keep, extract_labels(e, caps)}
      :nomatch -> {:keep, e}
    end
  end

  defp apply_stage(:unpack, %Entry{line: ""} = e), do: {:keep, e}

  defp apply_stage(:unpack, %Entry{} = e) do
    with {:ok, pairs} <- unpack_fields(e.line),
         {_, line} <- Enum.find(Enum.reverse(pairs), fn {key, value} -> key == "_entry" and is_binary(value) end) do
      # Unpack buffers fields before publication. Duplicates in this
      # object keep their last value; earlier parser extractions survive.
      fields =
        for {key, value} <- pairs,
            key != "_entry",
            is_binary(value),
            target = Entry.extraction_name(e, key),
            not Entry.extracted?(e, target),
            do: {logfmt_key(target), String.replace(value, "�", " ")}

      entry =
        Enum.reduce(fields, %{e | line: line}, fn {key, value}, acc ->
          Entry.put_label(acc, key, value, :parsed)
        end)

      {:keep, entry}
    else
      nil ->
        {:keep, e}

      {:error, details} ->
        {:keep, Entry.set_error(e, "JSONParserErr", details)}
    end
  end

  defp apply_stage({:line_format, tmpl}, %Entry{} = e), do: format_line(e, tmpl, e.labels)

  defp apply_stage({:line_format, tmpl, :ordinary_error_label}, %Entry{} = e),
    do: format_line(e, tmpl, Entry.ordinary_labels(e))

  defp apply_stage({:label_format, entries}, %Entry{} = e) do
    {formatted, _snapshot} =
      Enum.reduce(entries, {e, %{}}, fn
        {name, {:template, t}}, {acc, snapshot} ->
          snapshot = if map_size(snapshot) == 0, do: acc.labels, else: snapshot

          formatted =
            case Template.render(t, snapshot, e.line, e.timestamp_ns) do
              {:ok, value} -> Entry.put_label(acc, name, value, :parsed)
              {:error, details} -> template_error(acc, details)
            end

          {formatted, snapshot}

        {name, {:rename, src}}, {acc, snapshot} ->
          case Entry.fetch_label(acc, src) do
            {:ok, value} -> {acc |> Entry.put_label(name, value, :parsed) |> Entry.delete_label(src), snapshot}
            :error -> {acc, snapshot}
          end
      end)

    {:keep, formatted}
  end

  defp apply_stage({:drop, entries}, %Entry{} = e) do
    dropped =
      Enum.reduce(entries, e, fn {name, match}, acc ->
        value =
          if name in ["__error__", "__error_details__"],
            do: Entry.error_value(acc, name),
            else: Entry.label_value(acc, name)

        if drop_matches?(match, value) do
          Entry.drop_label(acc, name)
        else
          acc
        end
      end)

    {:keep, dropped}
  end

  defp apply_stage({:keep, entries}, %Entry{} = e) do
    kept =
      for {name, match} <- entries, value = Map.get(e.labels, name), keep_matches?(match, value), into: %{} do
        {name, value}
      end

    {:keep, Entry.keep_labels(e, kept)}
  end

  defp apply_stage(:decolorize, %Entry{} = e) do
    {:keep, %{e | line: strip_ansi(e.line)}}
  end

  defp apply_stage({:unwrap, _}, %Entry{} = e) do
    # Unwrap is a directive for the range aggregator; it does not filter or
    # transform records at the pipeline level. Pass-through here.
    {:keep, e}
  end

  defp template_error(entry, details), do: Entry.set_error(entry, "TemplateFormatErr", details)

  defp format_line(entry, template, labels) do
    case Template.render(template, labels, entry.line, entry.timestamp_ns) do
      {:ok, line} -> {:keep, %{entry | line: line}}
      {:error, details} -> {:keep, template_error(entry, details)}
    end
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------

  # Negative OR rejects the union: every individual negative must pass.
  defp line_matches?(op, {:or, values}, line) when op in [:not_contains, :not_match_re, :not_match_pattern],
    do: Enum.all?(values, &line_matches?(op, &1, line))

  defp line_matches?(op, {:or, values}, line), do: Enum.any?(values, &line_matches?(op, &1, line))

  defp line_matches?(:contains, {:string, s}, line), do: String.contains?(line, s)
  defp line_matches?(:not_contains, {:string, s}, line), do: not String.contains?(line, s)
  defp line_matches?(:match_re, {:re, re}, line), do: NIF.match_log_regex(re, line)
  defp line_matches?(:not_match_re, {:re, re}, line), do: not NIF.match_log_regex(re, line)
  defp line_matches?(:match_pattern, {:pattern, parts}, line), do: Pattern.filter_match?(parts, line)
  defp line_matches?(:not_match_pattern, {:pattern, parts}, line), do: not Pattern.filter_match?(parts, line)
  defp line_matches?(:contains, {:ip, matcher}, line), do: IP.matches?(matcher, line)
  defp line_matches?(:not_contains, {:ip, matcher}, line), do: not IP.matches?(matcher, line)

  # AND evaluates both operands even when the left is false. The right operand
  # can set an error that a surrounding OR subsequently reads. OR short-circuits.
  defp eval_label_filter({:and, l, r}, entry) do
    {left, entry} = eval_label_filter(l, entry)
    {right, entry} = eval_label_filter(r, entry)
    {left and right, entry}
  end

  defp eval_label_filter({:or, l, r}, entry) do
    case eval_label_filter(l, entry) do
      {true, entry} -> {true, entry}
      {false, entry} -> eval_label_filter(r, entry)
    end
  end

  defp eval_label_filter({:cmp, name, op, {:ip, matcher}}, entry) do
    result =
      cond do
        Entry.error_value(entry, "__error__") != "" -> true
        is_nil(Entry.label_value(entry, name)) -> false
        op == :eq -> IP.matches?(matcher, Entry.label_value(entry, name))
        op == :neq -> not IP.matches?(matcher, Entry.label_value(entry, name))
      end

    {result, entry}
  end

  defp eval_label_filter({:cmp, name, op, {type, expected}}, entry) when type in [:number, :duration_ns, :bytes] do
    actual = Entry.label_value(entry, name)

    case {actual, parse_filter_value(type, actual)} do
      {nil, _} ->
        {false, entry}

      {_, {:ok, value}} ->
        expected = if type == :number, do: expected / 1, else: expected
        {compare_number(op, value, expected), entry}

      {_, {:error, details}} ->
        {true, label_conversion_error(entry, details)}

      {actual, :error} ->
        kind = Atom.to_string(type)
        {true, label_conversion_error(entry, "invalid #{kind} value " <> Pulse.JSON.encode!(actual))}
    end
  end

  defp eval_label_filter({:cmp, name, op, value}, entry) do
    actual = if name == "__error__", do: Entry.error_value(entry, name), else: Entry.label_value(entry, name) || ""
    {eval_cmp(op, actual, value), entry}
  end

  defp eval_cmp(:eq, actual, {:string, v}), do: actual == v
  defp eval_cmp(:neq, actual, {:string, v}), do: actual != v
  defp eval_cmp(:re, actual, {:re, re}), do: NIF.match_log_regex(re, actual)
  defp eval_cmp(:nre, actual, {:re, re}), do: not NIF.match_log_regex(re, actual)
  defp eval_cmp(_, _, _), do: false

  defp compare_number(:eq, a, b), do: Number.compare("==", a, b)
  defp compare_number(:neq, a, b), do: Number.compare("!=", a, b)
  defp compare_number(:lt, a, b), do: Number.compare("<", a, b)
  defp compare_number(:lte, a, b), do: Number.compare("<=", a, b)
  defp compare_number(:gt, a, b), do: Number.compare(">", a, b)
  defp compare_number(:gte, a, b), do: Number.compare(">=", a, b)

  defp drop_matches?(:any, _v), do: true
  defp drop_matches?(_, nil), do: false
  defp drop_matches?({:eq, v}, actual), do: actual == v
  defp drop_matches?({:neq, v}, actual), do: actual != v
  defp drop_matches?({:re, re}, actual), do: NIF.match_log_regex(re, actual)
  defp drop_matches?({:nre, re}, actual), do: not NIF.match_log_regex(re, actual)

  defp keep_matches?(:any, _), do: true
  defp keep_matches?({:eq, v}, actual), do: actual == v
  defp keep_matches?({:neq, v}, actual), do: actual != v
  defp keep_matches?({:re, re}, actual), do: NIF.match_log_regex(re, actual)
  defp keep_matches?({:nre, re}, actual), do: not NIF.match_log_regex(re, actual)

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Stream and current metadata owners keep their names. Ordinary parsers
  # retain the first parsed target, including across later drops; explicit
  # expression parsers may replace an earlier extraction.
  defp extract_labels(entry, extracted, overwrite? \\ false) do
    Enum.reduce(extracted, entry, fn {name, value}, acc ->
      target = Entry.extraction_name(acc, name)

      if overwrite? or not Entry.extracted?(acc, target),
        do: Entry.put_label(acc, target, value, :parsed),
        else: acc
    end)
  end

  defp unpack_fields(<<"{", _::binary>> = line) do
    decoders = [
      object_finish: fn pairs, acc -> {{:object, Enum.reverse(pairs)}, acc} end,
      integer: fn _ -> :number end,
      float: fn _ -> :number end
    ]

    case JSON.decode(line, nil, decoders) do
      {{:object, pairs}, _, _rest} -> {:ok, pairs}
      _ -> {:error, json_object_error(line)}
    end
  end

  defp unpack_fields(_), do: {:error, "expecting json object(6), but it is not"}

  # Preserve object order/duplicates and numeric lexemes before flattening.
  # Arrays and nulls are not labels; unlike explicit extraction they are skipped.
  defp decode_json_labels(line) do
    decoders = [object_finish: fn pairs, acc -> {{:object, Enum.reverse(pairs)}, acc} end]

    case JSON.decode(quote_json_numbers(line), nil, decoders) do
      {{:object, pairs}, _, _rest} -> {:ok, flatten_json_labels(pairs, nil)}
      _ -> {:error, json_object_error(line)}
    end
  end

  defp quote_json_numbers(line) do
    # OTP normalizes -0 and inserts .0 before exponents even with number
    # callbacks. Quote numeric tokens first, leaving complete strings untouched;
    # label values are strings either way. JSON still validates the structure.
    Regex.replace(~r/"(?:\\.|[^"\\])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/s, line, fn
      <<?", _::binary>> = string -> string
      number -> "\"" <> number <> "\""
    end)
  end

  defp flatten_json_labels(pairs, prefix) do
    Enum.flat_map(pairs, fn {key, value} ->
      name = json_label_name(prefix, key)

      case value do
        {:object, nested} -> flatten_json_labels(nested, name)
        value when is_binary(value) and (prefix != nil or name != "") -> [{name, String.replace(value, "�", " ")}]
        value when is_boolean(value) and (prefix != nil or name != "") -> [{name, to_string(value)}]
        _ -> []
      end
    end)
  end

  defp json_label_name(prefix, key) when prefix in [nil, ""], do: logfmt_key(key)

  defp json_label_name(prefix, key) do
    case String.trim(key) do
      "" -> prefix
      key -> prefix <> "_" <> String.replace(key, ~r/[^a-zA-Z0-9_]/u, "_")
    end
  end

  defp json_object_error(line) do
    case skip_json_space(line) do
      <<"{", rest::binary>> ->
        case skip_json_space(rest) do
          <<byte, _::binary>> when byte not in [?", ?}] -> "Value looks like object, but can't find closing '}' symbol"
          _ -> "Malformed JSON error"
        end

      _ ->
        "Value looks like object, but can't find closing '}' symbol"
    end
  end

  defp skip_json_space(<<byte, rest::binary>>) when byte in [32, 9, 10, 13], do: skip_json_space(rest)
  defp skip_json_space(line), do: line

  defp extract_json_fields(entry, fields) do
    matches =
      for {{label, path}, index} <- Enum.with_index(fields),
          {:ok, value, position} <- [Json.fetch(entry.line, path)],
          do: {position, index, label, value}

    extracted = matches |> Enum.sort() |> Enum.map(fn {_, _, label, value} -> {label, value} end)
    entry = extract_labels(entry, extracted, true)

    Enum.reduce(fields, entry, fn {label, _path}, acc ->
      if Map.has_key?(acc.labels, label), do: acc, else: Entry.put_label(acc, label, "", :parsed)
    end)
  end

  defp extract_logfmt_fields(pairs, fields, _sources, entry) when map_size(fields) == 0 do
    extracted = for {key, value} <- pairs, name = logfmt_key(key), name != "", do: {name, value}
    {extract_labels(entry, extracted), false}
  end

  defp extract_logfmt_fields(pairs, fields, sources, entry) do
    entry =
      Enum.reduce(fields, entry, fn {label, _source}, acc ->
        if Entry.extraction_name(acc, label) == label, do: Entry.put_label(acc, label, "", :parsed), else: acc
      end)

    Enum.reduce_while(pairs, {entry, false}, fn {key, value}, {acc, _stopped?} ->
      key = logfmt_key(key)
      destination = Map.get(sources, key, key)
      target = Entry.extraction_name(acc, destination)

      cond do
        key == "" or not Map.has_key?(fields, destination) ->
          {:cont, {acc, false}}

        not Map.has_key?(fields, key) and Entry.extracted?(acc, key) ->
          {:cont, {acc, false}}

        target != destination and Entry.extracted?(acc, target) ->
          {:halt, {acc, true}}

        true ->
          {:cont, {Entry.put_label(acc, target, value, :parsed), false}}
      end
    end)
  end

  defp logfmt_key(key) do
    key = String.trim(key)
    key = if Regex.match?(~r/\A[0-9]/, key), do: "_" <> key, else: key
    String.replace(key, ~r/[^a-zA-Z0-9_]/u, "_")
  end

  defp parse_filter_value(:number, str), do: FloatParser.parse_with_error(str)
  defp parse_filter_value(:duration_ns, str), do: Quantity.duration_value(str)
  defp parse_filter_value(:bytes, str), do: Quantity.bytes_value(str)

  # Conversion failures keep the line and the first error, allowing later
  # __error__ filters to decide its fate. Details come from the same converters
  # used by unwrap, retaining their original Go diagnostics.
  defp label_conversion_error(entry, details) do
    if Entry.error_value(entry, "__error__") == "",
      do: Entry.set_error(entry, "LabelFilterErr", details),
      else: entry
  end

  # Recognize Loki's decolorizer language without discarding unmatched input.
  # Each candidate is scanned at most twice; neither body accepts a new marker.
  defp strip_ansi(line), do: strip_ansi(line, <<>>)

  defp strip_ansi(line, acc) do
    case :binary.match(line, [<<0x1B>>, <<0x9B::utf8>>]) do
      :nomatch ->
        if acc == <<>>, do: line, else: <<acc::binary, line::binary>>

      {offset, size} ->
        <<prefix::binary-size(^offset), marker::binary-size(^size), rest::binary>> = line

        case ansi_sequence(rest) do
          nil -> strip_ansi(rest, <<acc::binary, prefix::binary, marker::binary>>)
          tail -> strip_ansi(tail, <<acc::binary, prefix::binary>>)
        end
    end
  end

  defp ansi_sequence(<<char, rest::binary>>) when char in ~c"[]()#;?", do: ansi_sequence(rest)
  defp ansi_sequence(rest), do: ansi_bell(rest) || ansi_control(rest, 0, nil)

  # The BEL-terminated alternative takes priority, even across an apparent
  # control terminator. Its body is ASCII alphanumerics and semicolons only.
  defp ansi_bell(<<7, rest::binary>>), do: rest

  defp ansi_bell(<<char, rest::binary>>) when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char == ?;,
    do: ansi_bell(rest)

  defp ansi_bell(_), do: nil

  # Parameter components have at most four digits. A digit can itself be the
  # final byte, so retain the last valid endpoint when a longer candidate fails.
  defp ansi_control(<<char, rest::binary>>, digits, _last) when char in ?0..?9 and digits < 4,
    do: ansi_control(rest, digits + 1, rest)

  defp ansi_control(<<?;, rest::binary>>, _digits, last) when not is_nil(last), do: ansi_control(rest, 0, last)

  defp ansi_control(<<char, rest::binary>>, _digits, _last)
       when char in ?0..?9 or char in ?A..?P or char in ?f..?n or char in ~c"RZctqry=><~", do: rest

  defp ansi_control(_, _digits, last), do: last
end
