defmodule Pulse.Storage.S3.MetricLabelSummary do
  @moduledoc false

  # Each retained label has a COMPLETE value set over the segment. Large or
  # invalid sets are omitted independently, never truncated. Names are chosen
  # across every record, fewest values first, so a mixed batch still keeps
  # the selective labels (job, namespace, env...) of later records. Untracked
  # names are simply unknown. Missing labels have the Prometheus value "".
  @max_names 16
  @max_values 32
  @max_bytes 4096
  # Distinct candidate names tracked while building; later new names are unknown.
  @max_tracked 512
  @max_prefixes 64

  def build([]), do: nil

  def build(records) do
    case Enum.reduce_while(records, {0, %{}}, &track_record/2) do
      :invalid ->
        nil

      {count, tracked} ->
        {summary, _bytes} =
          tracked
          |> Enum.flat_map(&complete_set(&1, count))
          |> Enum.sort_by(fn {name, values} -> {MapSet.size(values), name} end)
          |> Enum.reduce({%{}, 2}, &add_label/2)

        if map_size(summary) > 0, do: summary
    end
  end

  @doc """
  Summarize exactly `names`, in priority order: when the byte budget is
  exhausted, later names are omitted (unknown) rather than earlier ones.
  """
  def build([], _names), do: nil

  def build(records, names) do
    names = Enum.take(names, @max_names)
    sets = Map.new(names, &{&1, MapSet.new()})
    sets = Enum.reduce_while(records, sets, &collect_record/2)

    {summary, _bytes} =
      names
      |> Enum.flat_map(fn name -> if values = Map.get(sets, name), do: [{name, values}], else: [] end)
      |> Enum.reduce({%{}, 2}, &add_label/2)

    if map_size(summary) > 0, do: summary
  end

  @doc """
  The summary of the union of the rows `summaries` describe: a name is kept
  only when every summary has it, with the union of their values, within the
  same bounds and in `names` priority order. Any unknown summary makes the
  union unknown.
  """
  def union(summaries, names) do
    if summaries != [] and Enum.all?(summaries, &is_map/1) do
      {summary, _bytes} =
        names
        |> Enum.take(@max_names)
        |> Enum.filter(fn name -> Enum.all?(summaries, &Map.has_key?(&1, name)) end)
        |> Enum.flat_map(&union_values(summaries, &1))
        |> Enum.reduce({%{}, 2}, &add_label/2)

      if map_size(summary) > 0, do: summary
    end
  end

  defp union_values(summaries, name) do
    values = summaries |> Enum.flat_map(&Map.fetch!(&1, name)) |> MapSet.new()
    if MapSet.size(values) <= @max_values, do: [{name, values}], else: []
  end

  defp collect_record(record, sets) do
    if Enum.all?(Map.keys(record.labels), &valid_utf8?/1) do
      # An overflowed (nil) set never recovers, so drop it; once none remain,
      # later records cannot add anything.
      sets =
        for {name, values} <- sets,
            values = collect(values, Map.get(record.labels, name, "")),
            into: %{},
            do: {name, values}

      if map_size(sets) == 0, do: {:halt, sets}, else: {:cont, sets}
    else
      # Native JSON materialization normalizes invalid UTF-8 keys, which
      # could collide with a selected name. Never summarize that case.
      {:halt, %{}}
    end
  end

  # A name absent from some records also has the value "".
  defp complete_set({_name, {_present, nil}}, _count), do: []
  defp complete_set({name, {present, values}}, count) when present == count, do: [{name, values}]

  defp complete_set({name, {_present, values}}, _count) do
    if values = collect(values, ""), do: [{name, values}], else: []
  end

  defp track_record(record, {count, tracked}) do
    if Enum.all?(Map.keys(record.labels), &valid_utf8?/1) do
      tracked = Enum.reduce(record.labels, tracked, &track_label(&1, &2, count))
      {:cont, {count + 1, tracked}}
    else
      # Native JSON materialization normalizes invalid UTF-8 keys, which
      # could collide with a selected name. Never summarize that case.
      {:halt, :invalid}
    end
  end

  defp track_label({name, value}, tracked, count) do
    case tracked do
      %{^name => {present, values}} ->
        %{tracked | name => {present + 1, collect(values, value)}}

      _ when map_size(tracked) < @max_tracked and name != "__name__" ->
        if valid_name?(name), do: Map.put(tracked, name, {1, first_values(value, count)}), else: tracked

      _ ->
        tracked
    end
  end

  # Every earlier record lacked a name first seen now.
  defp first_values(value, 0), do: collect(MapSet.new(), value)
  defp first_values(value, _count), do: collect(MapSet.new([""]), value)

  defp add_label({name, values}, {summary, bytes}) when map_size(summary) < @max_names do
    values = values |> Enum.map(&:binary.copy/1) |> Enum.sort()
    added = IO.iodata_length(Pulse.JSON.encode_to_iodata!(%{name => values}))

    if bytes + added <= @max_bytes,
      do: {Map.put(summary, :binary.copy(name), values), bytes + added},
      else: {summary, bytes}
  end

  defp add_label(_label, acc), do: acc

  defp collect(nil, _value), do: nil

  defp collect(values, value) do
    if valid_value?(value) do
      values = MapSet.put(values, value)
      if MapSet.size(values) <= @max_values, do: values
    end
  end

  def parse(summary) when is_map(summary) and map_size(summary) in 1..@max_names do
    if Enum.all?(summary, fn {name, values} ->
         valid_name?(name) and is_list(values) and length(values) in 1..@max_values and
           Enum.all?(values, &valid_value?/1)
       end) and IO.iodata_length(Pulse.JSON.encode_to_iodata!(summary)) <= @max_bytes,
       do: summary
  end

  def parse(_), do: nil

  @doc "Exact-equality pruning, as used by log error-label summaries."
  def matches?(nil, _matchers), do: true

  def matches?(summary, matchers) do
    Enum.all?(matchers, fn
      {name, :eq, value} ->
        case Map.fetch(summary, name) do
          {:ok, values} -> value in values
          :error -> true
        end

      _ ->
        true
    end)
  end

  @doc """
  Compile metric matchers once per query into tests that can run against a
  complete value set. Matchers whose meaning cannot be decided from values
  alone are dropped: they never prune.

  Regex patterns are recognized only in the fully anchored, dot-all form that
  PromQL pushes to storage (`Pulse.QueryRegex.anchor/1`), and only for
  literal, alternation, grouping and literal-prefix shapes. Anything else,
  including flags and `\\Q` quoting, stays unknown.
  """
  def plan(matchers) do
    Enum.flat_map(matchers, fn
      {name, op, value} when op in [:eq, :neq] and is_binary(name) and is_binary(value) ->
        [{name, op, value}]

      {name, op, pattern} when op in [:re, :nre] and is_binary(name) and is_binary(pattern) ->
        case regex_shape(pattern) do
          :unknown -> []
          shape -> [{name, op, shape}]
        end

      _ ->
        []
    end)
    |> Enum.group_by(fn {name, _op, _expected} -> name end, fn {_name, op, expected} -> {op, expected} end)
  end

  @doc """
  Can a segment with these complete value sets match every planned matcher?
  `fetch` returns `{:ok, values}` for a complete set or `:error` when unknown.
  One value must satisfy all matchers for the same name. Different names are
  tested independently, so this never proves a matching sample exists.
  """
  def satisfiable?(plan, fetch) do
    Enum.all?(plan, fn {name, matchers} ->
      values_may_match?(fetch.(name), matchers)
    end)
  end

  defp values_may_match?(:error, _matchers), do: true

  defp values_may_match?({:ok, values}, matchers) do
    Enum.any?(values, fn value ->
      Enum.all?(matchers, fn {op, expected} -> value_may_match?(op, expected, value) end)
    end)
  end

  defp value_may_match?(:eq, expected, value), do: value == expected
  defp value_may_match?(:neq, expected, value), do: value != expected
  defp value_may_match?(:re, shape, value), do: regex_result(shape, value) != false
  defp value_may_match?(:nre, shape, value), do: regex_result(shape, value) != true

  # true: certainly matches; false: certainly not; :maybe: only a necessary
  # literal prefix is known.
  defp regex_result(:any, _value), do: true

  defp regex_result({exact, prefixes}, value) do
    if MapSet.member?(exact, value),
      do: true,
      else: Enum.reduce_while(prefixes, false, &prefix_result(&1, &2, value))
  end

  defp prefix_result({prefix, complete?}, acc, value) do
    cond do
      not String.starts_with?(value, prefix) -> {:cont, acc}
      complete? -> {:halt, true}
      true -> {:cont, :maybe}
    end
  end

  @anchor_open "(?s:\\A(?:"
  @anchor_close ")\\z)"
  @anchor_bytes byte_size(@anchor_open) + byte_size(@anchor_close)

  @doc false
  def regex_shape(pattern) do
    with true <- byte_size(pattern) >= @anchor_bytes,
         true <- String.starts_with?(pattern, @anchor_open) and String.ends_with?(pattern, @anchor_close),
         inner = binary_part(pattern, byte_size(@anchor_open), byte_size(pattern) - @anchor_bytes),
         {:ok, tokens} <- tokenize(inner, []),
         true <- balanced?(tokens, 0) do
      alternatives = tokens |> branches() |> Enum.flat_map(&branch_shape/1)
      exact = for {:exact, literal} <- alternatives, into: MapSet.new(), do: literal
      prefixes = for {:prefix, literal, complete?} <- alternatives, do: {literal, complete?}

      cond do
        {"", true} in prefixes -> :any
        {"", false} in prefixes or length(prefixes) > @max_prefixes -> :unknown
        true -> {exact, prefixes}
      end
    else
      _ -> :unknown
    end
  end

  # Tokens: {:lit, binary}, :open, :close, :alt, {:meta, char}. Classes and
  # other escapes are opaque metas; unsupported syntax aborts.
  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}
  defp tokenize(<<"\\Q", _::binary>>, _acc), do: :unknown

  defp tokenize(<<"\\", char, rest::binary>>, acc)
       when char in ?!..?/ or char in ?:..?@ or char in ?[..?` or char in ?{..?~,
       do: tokenize(rest, [{:lit, <<char>>} | acc])

  defp tokenize(<<"\\", _::utf8, rest::binary>>, acc), do: tokenize(rest, [{:meta, ?\\} | acc])
  defp tokenize(<<"(?:", rest::binary>>, acc), do: tokenize(rest, [:open | acc])
  defp tokenize(<<"(?", _::binary>>, _acc), do: :unknown
  defp tokenize(<<"(", rest::binary>>, acc), do: tokenize(rest, [:open | acc])
  defp tokenize(<<")", rest::binary>>, acc), do: tokenize(rest, [:close | acc])
  defp tokenize(<<"|", rest::binary>>, acc), do: tokenize(rest, [:alt | acc])

  defp tokenize(<<"[", rest::binary>>, acc) do
    rest = String.replace_prefix(rest, "^", "")
    rest = String.replace_prefix(rest, "]", "")

    case skip_class(rest) do
      {:ok, tail} -> tokenize(tail, [{:meta, ?[} | acc])
      :unknown -> :unknown
    end
  end

  defp tokenize(<<char, rest::binary>>, acc) when char in ~c".*+?{}^$]\\", do: tokenize(rest, [{:meta, char} | acc])

  defp tokenize(<<char::utf8, rest::binary>>, acc), do: tokenize(rest, [{:lit, <<char::utf8>>} | acc])
  defp tokenize(_invalid, _acc), do: :unknown

  defp skip_class(<<"]", rest::binary>>), do: {:ok, rest}
  defp skip_class(<<"\\", _::utf8, rest::binary>>), do: skip_class(rest)

  defp skip_class(<<"[:", rest::binary>>) do
    case :binary.match(rest, ":]") do
      {offset, 2} -> skip_class(binary_part(rest, offset + 2, byte_size(rest) - offset - 2))
      :nomatch -> :unknown
    end
  end

  defp skip_class(<<_::utf8, rest::binary>>), do: skip_class(rest)
  defp skip_class(_), do: :unknown

  defp balanced?([], depth), do: depth == 0
  defp balanced?([:open | rest], depth), do: balanced?(rest, depth + 1)
  defp balanced?([:close | _], 0), do: false
  defp balanced?([:close | rest], depth), do: balanced?(rest, depth - 1)
  defp balanced?([_ | rest], depth), do: balanced?(rest, depth)

  # Split at top-level `|`.
  defp branches(tokens) do
    {branches, current, _depth} =
      Enum.reduce(tokens, {[], [], 0}, fn
        :alt, {branches, current, 0} -> {[Enum.reverse(current) | branches], [], 0}
        :open = token, {branches, current, depth} -> {branches, [token | current], depth + 1}
        :close = token, {branches, current, depth} -> {branches, [token | current], depth - 1}
        token, {branches, current, depth} -> {branches, [token | current], depth}
      end)

    Enum.reverse([Enum.reverse(current) | branches])
  end

  defp branch_shape([:open | rest] = tokens) do
    case whole_group(rest, 0, []) do
      {:ok, inner} -> inner |> branches() |> Enum.flat_map(&branch_shape/1)
      :error -> literal_shape(tokens)
    end
  end

  defp branch_shape(tokens), do: literal_shape(tokens)

  # The inner tokens when the group closes exactly at the end of the branch.
  defp whole_group([:close], 0, acc), do: {:ok, Enum.reverse(acc)}
  defp whole_group([:close | _], 0, _acc), do: :error
  defp whole_group([:close | rest], depth, acc), do: whole_group(rest, depth - 1, [:close | acc])
  defp whole_group([:open | rest], depth, acc), do: whole_group(rest, depth + 1, [:open | acc])
  defp whole_group([token | rest], depth, acc), do: whole_group(rest, depth, [token | acc])
  defp whole_group([], _depth, _acc), do: :error

  defp literal_shape(tokens) do
    {literals, rest} = Enum.split_while(tokens, &match?({:lit, _}, &1))
    literals = Enum.map(literals, fn {:lit, literal} -> literal end)

    case rest do
      [] ->
        [{:exact, IO.iodata_to_binary(literals)}]

      [{:meta, ?.}, {:meta, ?*}] ->
        [{:prefix, IO.iodata_to_binary(literals), true}]

      # A quantifier applies only to the preceding literal.
      [{:meta, quantifier} | _] when quantifier in ~c"*+?{" ->
        [{:prefix, literals |> Enum.drop(-1) |> IO.iodata_to_binary(), false}]

      _ ->
        [{:prefix, IO.iodata_to_binary(literals), false}]
    end
  end

  defp valid_name?(name), do: is_binary(name) and byte_size(name) in 1..128 and String.valid?(name)
  defp valid_value?(value), do: is_binary(value) and byte_size(value) <= 256 and String.valid?(value)
  defp valid_utf8?(value), do: is_binary(value) and String.valid?(value)
end
