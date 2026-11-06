defmodule Pulse.Storage.S3.TraceAttributeSummary do
  @moduledoc false
  # Bounded, complete sets of the string values each resource ("r") and span
  # ("s") attribute key holds across a trace segment's rows: exactly the
  # query projections `query_traces` `resource`/`attributes` and their regex
  # filters compare, taken from the records encoded into the segment payload.
  #
  # Per owner, `keys` maps a key to its sorted values, or to nil when it holds
  # too many (present, values unknown). `complete?` additionally proves that
  # no unlisted key holds a string value in any row. A listed set lets a
  # filter on that key skip the source; with `complete?`, so does a filter on
  # an unlisted key. Anything else always reads. Non-string projections never
  # match string filters, so they are not tracked.

  alias Pulse.Storage.S3.TraceSummary

  @owners [{"r", :resource, :resource_regex}, {"s", :attributes, :attributes_regex}]
  @max_keys 64
  @max_key_bytes 256
  @max_values 8
  @max_value_bytes 96
  @segment_bytes 384
  @page_bytes 512

  @type owner :: {%{String.t() => [String.t()] | nil}, boolean()}
  @type t :: %{String.t() => owner()} | nil

  def build(records) do
    Map.new(@owners, fn {owner, field, _} -> {owner, collect(records, field)} end) |> fit(@segment_bytes)
  end

  # A row without an attribute map leaves every key's values unknown.
  defp collect(records, field) do
    if Enum.all?(records, &is_map(Map.get(&1, field))) do
      {keys, complete?} =
        Enum.reduce(records, {%{}, true}, fn record, acc -> Enum.reduce(Map.get(record, field), acc, &add_value/2) end)

      {Map.new(keys, fn {key, set} -> {key, if(set != :many, do: set |> MapSet.to_list() |> Enum.sort())} end),
       complete?}
    else
      {%{}, false}
    end
  end

  defp add_value({_key, value}, acc) when not is_binary(value), do: acc

  defp add_value({key, value}, {keys, complete?}) do
    case keys do
      %{^key => :many} ->
        {keys, complete?}

      %{^key => set} ->
        {Map.put(keys, key, put_value(set, value)), complete?}

      _ ->
        if valid_key?(key) and map_size(keys) < @max_keys,
          do: {Map.put(keys, :binary.copy(key), put_value(MapSet.new(), value)), complete?},
          else: {keys, false}
    end
  end

  defp put_value(set, value) do
    if valid_value?(value) do
      set = MapSet.put(set, value)
      if MapSet.size(set) > @max_values, do: :many, else: set
    else
      :many
    end
  end

  defp valid_key?(key), do: is_binary(key) and byte_size(key) in 1..@max_key_bytes and String.valid?(key)
  defp valid_value?(value), do: is_binary(value) and byte_size(value) <= @max_value_bytes and String.valid?(value)

  @doc false
  # The value sets native trace compaction collected for one output, by the
  # same rules as `build/1`: `{complete?, [{key, values | nil}]}` per owner.
  def from_native({_, _} = resource, {_, _} = span),
    do: fit(%{"r" => native_owner(resource), "s" => native_owner(span)}, @segment_bytes)

  defp native_owner({complete?, keys}), do: {Map.new(keys), complete?}

  @doc false
  # The union over sources whose rows together are exactly (or a subset of)
  # the target's rows: a compaction replacement or a manifest page. Unknown
  # sources keep only values every other source proves.
  def merge(summaries, target \\ :page) do
    Map.new(@owners, fn {owner, _, _} ->
      parts = Enum.map(summaries, &((&1 && &1[owner]) || {%{}, false}))
      {owner, merge_owner(parts)}
    end)
    |> fit(if(target == :segment, do: @segment_bytes, else: @page_bytes))
  end

  defp merge_owner(parts) do
    complete? = Enum.all?(parts, &elem(&1, 1))
    names = parts |> Enum.flat_map(&Map.keys(elem(&1, 0))) |> Enum.uniq()

    keys =
      Enum.flat_map(names, fn name ->
        case merge_values(parts, name, []) do
          nil when complete? -> [{name, nil}]
          nil -> []
          values -> [{name, values}]
        end
      end)

    if length(keys) <= @max_keys,
      do: {Map.new(keys), complete?},
      else: {keys |> Enum.reject(&is_nil(elem(&1, 1))) |> Enum.take(@max_keys) |> Map.new(), false}
  end

  defp merge_values([], _name, acc) do
    values = acc |> Enum.uniq() |> Enum.sort()
    if length(values) <= @max_values, do: values
  end

  defp merge_values([{keys, complete?} | rest], name, acc) do
    case keys do
      %{^name => [_ | _] = values} -> merge_values(rest, name, values ++ acc)
      %{^name => _} -> nil
      _ when complete? -> merge_values(rest, name, acc)
      _ -> nil
    end
  end

  # Shrink to `budget` encoded bytes, costliest value set first: a complete
  # owner keeps the key name (nil), an incomplete one drops it. Should key
  # names alone not fit, give up span and then resource completeness.
  defp fit(owners, budget) do
    variants = [owners, incomplete(owners, ["s"]), incomplete(owners, ["s", "r"])]
    owners = Enum.find_value(variants, &shrink(&1, budget))
    if owners && Enum.any?(owners, fn {_, {keys, complete?}} -> complete? or keys != %{} end), do: owners
  end

  defp incomplete(owners, names) do
    Map.new(owners, fn {owner, {keys, complete?}} ->
      if owner in names,
        do: {owner, {Map.reject(keys, &is_nil(elem(&1, 1))), false}},
        else: {owner, {keys, complete?}}
    end)
  end

  defp shrink(owners, budget) do
    if wire_bytes(owners) <= budget, do: owners, else: shrink_values(owners, budget)
  end

  defp shrink_values(owners, budget) do
    owners
    |> Enum.flat_map(fn {owner, {keys, complete?}} ->
      for {key, [_ | _] = values} <- keys, do: {owner, key, complete?, json_bytes(values)}
    end)
    |> Enum.sort_by(&elem(&1, 3), :desc)
    |> Enum.reduce_while(owners, fn {owner, key, complete?, _cost}, owners ->
      owners = forget_values(owners, owner, key, complete?)
      if wire_bytes(owners) <= budget, do: {:halt, owners}, else: {:cont, owners}
    end)
    |> then(&if(wire_bytes(&1) <= budget, do: &1))
  end

  defp forget_values(owners, owner, key, true), do: put_in(owners, [owner, Access.elem(0), key], nil)
  defp forget_values(owners, owner, key, false), do: update_in(owners, [owner, Access.elem(0)], &Map.delete(&1, key))

  defp json_bytes(value), do: IO.iodata_length(Pulse.JSON.encode_to_iodata!(value))
  defp wire_bytes(owners), do: owners |> to_wire() |> json_bytes()

  def to_wire(nil), do: nil

  def to_wire(owners) do
    Enum.reduce(owners, %{"v" => 1}, fn
      {_owner, {keys, false}}, wire when keys == %{} -> wire
      {owner, {keys, true}}, wire -> wire |> Map.put(owner, keys) |> Map.put(owner <> "c", true)
      {owner, {keys, false}}, wire -> Map.put(wire, owner, keys)
    end)
  end

  def parse(%{"v" => 1} = wire) do
    owners = Map.new(@owners, fn {owner, _, _} -> {owner, parse_owner(wire[owner], wire[owner <> "c"] == true)} end)
    if Enum.any?(owners, fn {_, {keys, complete?}} -> complete? or keys != %{} end), do: owners
  end

  def parse(_wire), do: nil

  defp parse_owner(keys, complete?) when is_map(keys) and map_size(keys) <= @max_keys do
    if Enum.all?(keys, fn {key, values} -> valid_key?(key) and valid_values?(values) end),
      do:
        {Map.new(keys, fn {key, values} -> {:binary.copy(key), values && Enum.map(values, &:binary.copy/1)} end),
         complete?},
      else: {%{}, false}
  end

  defp parse_owner(_keys, _complete?), do: {%{}, false}

  defp valid_values?(nil), do: true

  defp valid_values?([_ | _] = values), do: length(values) <= @max_values and Enum.all?(values, &valid_value?/1)

  defp valid_values?(_values), do: false

  @doc "Whether a source with this summary may hold a span matching the `query_traces` attribute filters in `opts`."
  def matches?(nil, _opts), do: true

  def matches?(owners, opts) do
    Enum.all?(@owners, fn {owner, exact, regex} ->
      {keys, complete?} = Map.get(owners, owner, {%{}, false})

      all_filters?(opts[exact], &exact_match?(keys, complete?, &1, &2)) and
        all_filters?(opts[regex], &regex_match?(keys, complete?, &1, &2))
    end)
  end

  defp all_filters?(filters, fun) when is_map(filters), do: Enum.all?(filters, fn {key, value} -> fun.(key, value) end)
  defp all_filters?(_filters, _fun), do: true

  # Only string values are proven; another wanted type may match an untracked
  # non-string projection.
  defp exact_match?(keys, complete?, key, value) when is_binary(key) and is_binary(value) do
    case Map.fetch(keys, key) do
      {:ok, nil} -> true
      {:ok, values} -> value in values
      :error -> not complete?
    end
  end

  defp exact_match?(_keys, _complete?, _key, _value), do: true

  defp regex_match?(keys, complete?, key, pattern) when is_binary(key) and is_binary(pattern) do
    case Map.fetch(keys, key) do
      {:ok, nil} -> true
      {:ok, values} -> Enum.any?(values, &TraceSummary.regex_match?(pattern, &1))
      :error -> not complete?
    end
  end

  defp regex_match?(_keys, _complete?, _key, _pattern), do: true
end
