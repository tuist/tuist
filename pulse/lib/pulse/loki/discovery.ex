defmodule Pulse.Loki.Discovery do
  @moduledoc """
  Loki label, label-value and series discovery over stored log streams.

  Stream labels are the string values of a record's `resource` (where Loki
  push keeps stream labels and OTLP keeps resource attributes) plus the
  promoted service as `service_name`. Empty values are absent, as in Loki.
  Selection reuses the log query's stream matchers, so a selector discovers
  exactly the streams a log query with it would read.

  Results are complete or fail whole: more than 5,000 entries or 1 MiB of
  output is `:query_resource_limit`, never a truncated list.
  """

  alias Pulse.LogQL.AST
  alias Pulse.LogQL.StreamMatchers
  alias Pulse.QueryRunner
  alias Pulse.Record.Log
  alias Pulse.Storage

  @entries 5000
  @bytes 1_048_576
  @reference_records 100_000

  @type mode :: :names | :values | :series

  @doc """
  Discover `mode` over the tenant's streams in `[start_ns, end_ns]`.

  `selectors` is a list of parsed stream selectors; their union is
  discovered. An empty list discovers all streams within the same budgets.
  """
  @spec query(String.t(), mode(), String.t(), [AST.Selector.t()], map()) :: {:ok, binary()} | {:error, term()}
  def query(tenant, mode, key, selectors, times) when mode in [:names, :values, :series] do
    with :ok <- validate(mode, key, selectors) do
      QueryRunner.run(
        tenant,
        :discovery,
        fn deadline ->
          base =
            [start_ts: times[:start_ns], end_ts: times[:end_ns]] ++
              QueryRunner.storage_opts(deadline, @reference_records)

          selectors
          |> branches()
          |> Enum.reduce_while({:ok, []}, &discover_branch(&1, &2, tenant, mode, key, base))
          |> merge(mode)
        end,
        times
      )
      |> budget_error()
    end
  end

  defp discover_branch({service, matchers}, {:ok, acc}, tenant, mode, key, base) do
    opts = base |> put_present(:service, service) |> Keyword.put(:matchers, matchers)

    case Storage.log_discovery_json(tenant, Atom.to_string(mode), key, opts) do
      {:ok, json} -> {:cont, {:ok, [json | acc]}}
      {:error, _} = error -> {:halt, error}
    end
  end

  # Every native or reference dictionary budget is a result-size limit.
  defp budget_error({:error, :query_resource_limit}), do: {:error, :query_result_limit}
  defp budget_error(result), do: result

  defp validate(:values, key, _selectors) when not is_binary(key) or key == "" or byte_size(key) > 256,
    do: {:error, {:invalid_query_parameter, "name"}}

  defp validate(_mode, _key, selectors) when length(selectors) > 16, do: {:error, {:invalid_query_parameter, "match[]"}}
  defp validate(_mode, _key, _selectors), do: :ok

  # No selector discovers every stream; each selector is one storage pass.
  defp branches([]), do: [{nil, []}]
  defp branches(selectors), do: Enum.map(selectors, &StreamMatchers.split(&1.matchers))

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  # One selector's native output is already the final, sorted answer. Unions
  # re-sort the combined entries under the same budgets.
  defp merge({:ok, [json]}, _mode), do: {:ok, json}

  defp merge({:ok, parts}, mode) do
    parts
    |> Enum.flat_map(&Pulse.JSON.decode!/1)
    |> Enum.map(&entry(&1, mode))
    |> finish()
  end

  defp merge(error, _mode), do: error

  defp entry(labels, :series) when is_map(labels), do: series_entry(Enum.sort(labels))
  defp entry(value, _mode) when is_binary(value), do: {value, encode(value)}

  @doc false
  # Record-backed reference for adapters without native discovery, with
  # the same label projection, ordering and budgets.
  def reference(backend, tenant, mode, key, opts) when is_binary(mode),
    do: reference(backend, tenant, String.to_existing_atom(mode), key, opts)

  def reference(backend, tenant, mode, key, opts) when mode in [:names, :values, :series] do
    with {:ok, records} <- backend.query(:logs, tenant, Keyword.delete(opts, :limit)),
         {:ok, streams} <- Enum.reduce_while(records, {:ok, MapSet.new()}, &collect_stream/2) do
      streams |> Enum.flat_map(&project(&1, mode, key)) |> finish()
    end
  end

  defp collect_stream(record, {:ok, streams}) do
    streams = MapSet.put(streams, labels(record))
    if MapSet.size(streams) > @entries * 4, do: {:halt, {:error, :query_resource_limit}}, else: {:cont, {:ok, streams}}
  end

  @doc false
  def labels(%Log{resource: resource, service: service}) do
    stream =
      for {name, value} <- resource || %{}, is_binary(name), name != "", is_binary(value), value != "", into: %{} do
        {name, value}
      end

    if is_binary(service) and service != "", do: Map.put_new(stream, "service_name", service), else: stream
  end

  defp project(stream, :names, _key), do: Enum.map(Map.keys(stream), &{&1, encode(&1)})

  defp project(stream, :values, key) do
    case Map.fetch(stream, key) do
      {:ok, value} -> [{value, encode(value)}]
      :error -> []
    end
  end

  defp project(stream, :series, _key), do: [series_entry(Enum.sort(stream))]

  defp series_entry(pairs) do
    key = Enum.map_join(pairs, fn {name, value} -> name <> <<0xFF>> <> value <> <<0xFF>> end)
    body = Enum.map_intersperse(pairs, ",", fn {name, value} -> [encode(name), ":", encode(value)] end)
    {key, IO.iodata_to_binary(["{", body, "}"])}
  end

  defp finish(entries) do
    entries = entries |> Map.new() |> Enum.sort_by(&elem(&1, 0))
    encoded = ["[", Enum.map_intersperse(entries, ",", &elem(&1, 1)), "]"]

    if length(entries) > @entries or IO.iodata_length(encoded) > @bytes,
      do: {:error, :query_resource_limit},
      else: {:ok, IO.iodata_to_binary(encoded)}
  end

  defp encode(value), do: Pulse.JSON.encode!(value)
end
