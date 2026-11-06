defmodule Pulse.PromQL.Discovery do
  @moduledoc "Complete, sample-backed metric dictionaries with shared query admission and no truncation."

  alias Pulse.Codec.NIF
  alias Pulse.PromQL.Parser
  alias Pulse.QueryRunner
  alias Pulse.Storage

  @minimum -9_223_372_036_854_775_808
  @maximum 9_223_372_036_854_775_807
  @entries 5000
  @bytes 1_048_576

  def query(tenant, mode, key, selectors, opts \\ %{}) do
    with :ok <- validate(mode, key, selectors, opts) do
      QueryRunner.run(tenant, :discovery, &run(tenant, mode, key, selectors, opts, &1), opts)
    end
  end

  defp run(tenant, mode, key, selectors, opts, deadline) do
    with {:ok, parsed} <- parse_selectors(selectors) do
      storage = [start_ts: Map.get(opts, :start_ts_ns, @minimum), end_ts: Map.get(opts, :end_ts_ns, @maximum)]
      Storage.metric_discovery_json(tenant, mode, key, parsed, storage ++ QueryRunner.storage_opts(deadline))
    end
  end

  defp validate(mode, key, selectors, opts) do
    with true <- mode in ["names", "values", "series"],
         true <- valid_key?(mode, key),
         true <- valid_selectors?(selectors),
         true <- mode != "series" or selectors != [],
         true <- valid_times?(opts),
         do: :ok,
         else: (_ -> {:error, :invalid_discovery_parameters})
  end

  defp valid_key?(mode, key) when is_binary(key),
    do: String.valid?(key) and byte_size(key) <= 256 and if(mode == "values", do: key != "", else: key == "")

  defp valid_key?(_, _), do: false

  defp valid_selectors?(selectors) when is_list(selectors) and length(selectors) <= 16 do
    Enum.all?(selectors, &(is_binary(&1) and byte_size(&1) in 1..16_384)) and
      Enum.reduce(selectors, 0, &(byte_size(&1) + &2)) <= 16_384
  end

  defp valid_selectors?(_), do: false

  defp valid_times?(opts) do
    start = Map.get(opts, :start_ts_ns, @minimum)
    finish = Map.get(opts, :end_ts_ns, @maximum)

    is_integer(start) and is_integer(finish) and start in @minimum..@maximum and
      finish in @minimum..@maximum and start <= finish
  end

  defp parse_selectors(selectors) do
    selectors |> Enum.reduce_while({:ok, []}, &parse_selector/2) |> validate_parsed()
  end

  defp parse_selector(selector, {:ok, acc}) do
    case Parser.parse(selector) do
      {:ok, {:selector, matchers, 0}} -> {:cont, {:ok, [matchers | acc]}}
      _ -> {:halt, {:error, :invalid_discovery_selector}}
    end
  end

  defp validate_parsed({:ok, parsed}) do
    all = List.flatten(parsed)

    valid =
      length(all) <= 64 and
        Enum.count(all, fn {_, op, _} -> op in [:re, :nre] end) <= 8 and
        Enum.all?(all, fn {name, _, _} -> byte_size(name) <= 256 end) and
        Enum.reduce(all, 0, fn {name, _, value}, n -> n + byte_size(name) + byte_size(value) end) <= 16_384

    if valid, do: {:ok, Enum.reverse(parsed)}, else: {:error, :invalid_discovery_selector}
  end

  defp validate_parsed(error), do: error

  @doc false
  def reference(backend, tenant, mode, key, selectors, opts) do
    # Older adapters must honor max_records. The sentinel also catches an
    # adapter applying that bound as a result limit instead of an error.
    opts = Keyword.drop(opts, [:limit, :matchers]) |> Keyword.put(:max_records, 100_001)

    with {:ok, rows} <- backend.query(:metrics, tenant, opts),
         true <- length(rows) <= 100_000 do
      state = %{entries: %{}, work: 0, probes: 0, bytes: 0, previous: nil}
      rows |> Enum.reduce_while({:ok, state}, &accumulate(&1, &2, mode, key, selectors)) |> finish_reference()
    else
      false -> {:error, :query_sample_limit}
      error -> error
    end
  end

  defp accumulate(row, {:ok, state}, mode, key, selectors) do
    case observe(row, %{state | work: state.work + 1}, mode, key, selectors) do
      {:ok, state} -> {:cont, {:ok, state}}
      error -> {:halt, error}
    end
  end

  defp finish_reference({:ok, state}) do
    json = state.entries |> Enum.sort() |> Enum.map(&elem(&1, 1)) |> Pulse.JSON.encode!()
    if byte_size(json) <= @bytes - 32, do: {:ok, json}, else: {:error, :query_resource_limit}
  end

  defp finish_reference(error), do: error

  defp observe(_, %{work: work}, _, _, _) when work > 5_000_000, do: {:error, :query_work_limit}

  defp observe(%{labels: labels}, %{previous: previous} = state, _, _, _) when is_map(labels) and labels == previous,
    do: {:ok, state}

  defp observe(%{labels: labels}, state, mode, key, selectors) when is_map(labels) do
    with :ok <- validate_labels(labels),
         {:ok, state} <- charge(state, labels, selectors) do
      state = %{state | previous: labels}

      if selectors == [] or Enum.any?(selectors, &matches?(labels, &1)),
        do: collect(state, labels, mode, key),
        else: {:ok, state}
    end
  end

  defp observe(_, _, _, _, _), do: {:error, :invalid_stored_sample}

  defp validate_labels(labels) do
    if Enum.all?(labels, fn {k, v} ->
         is_binary(k) and k != "" and String.valid?(k) and is_binary(v) and String.valid?(v)
       end), do: :ok, else: {:error, :invalid_stored_sample}
  end

  defp charge(state, labels, selectors) do
    bytes = Enum.reduce(labels, 0, fn {k, v}, n -> n + byte_size(k) + byte_size(v) + 2 end)
    probes = state.probes + bytes
    work = state.work + 1 + map_size(labels) + Enum.reduce(selectors, 0, &(length(&1) + &2))

    cond do
      bytes > 65_536 or probes > 16_777_216 or map_size(labels) > 1024 -> {:error, :query_resource_limit}
      work > 5_000_000 -> {:error, :query_work_limit}
      true -> {:ok, %{state | probes: probes, work: work}}
    end
  end

  defp matches?(labels, matchers) do
    Enum.all?(matchers, fn {name, op, expected} -> match_value?(Map.get(labels, name, ""), op, expected) end)
  end

  defp match_value?(value, :eq, expected), do: value == expected
  defp match_value?(value, :neq, expected), do: value != expected
  defp match_value?(value, :re, expected), do: NIF.match_metric_regex(Pulse.QueryRegex.anchor(expected), value)
  defp match_value?(value, :nre, expected), do: not NIF.match_metric_regex(Pulse.QueryRegex.anchor(expected), value)

  defp collect(state, labels, mode, key) do
    labels = Map.reject(labels, fn {_, value} -> value == "" end)
    entries = projected(labels, mode, key)
    Enum.reduce_while(entries, {:ok, state}, fn entry, {:ok, state} -> insert(entry, state) end)
  end

  defp projected(labels, "series", _) do
    key =
      for {name, value} <- Enum.sort(labels),
          part <- [name, value],
          into: "",
          do: :binary.replace(part, <<0>>, <<0, 1>>, [:global]) <> <<0, 0>>

    [{key, labels}]
  end

  defp projected(labels, "names", _), do: Enum.map(Map.keys(labels), &{&1, &1})
  defp projected(labels, "values", key), do: if(Map.has_key?(labels, key), do: [{labels[key], labels[key]}], else: [])

  defp insert({id, value}, state) do
    cond do
      Map.has_key?(state.entries, id) ->
        {:cont, {:ok, state}}

      map_size(state.entries) == @entries or state.bytes + byte_size(id) > @bytes ->
        {:halt, {:error, :query_resource_limit}}

      true ->
        {:cont, {:ok, %{state | bytes: state.bytes + byte_size(id), entries: Map.put(state.entries, id, value)}}}
    end
  end
end
