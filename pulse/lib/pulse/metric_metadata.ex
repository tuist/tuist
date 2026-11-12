defmodule Pulse.MetricMetadata do
  @moduledoc """
  Retained Prometheus metric metadata (type, help and unit per metric
  family) for `GET /api/v1/metadata`, which Grafana's metric browser, query
  hints and Metrics Drilldown read.

  Remote-write senders send metadata alongside or apart from samples. Each
  tenant keeps one bounded set: every distinct `{type, help, unit}` variant of
  a metric is kept with the day it was last reported, as Prometheus reports
  every variant its targets expose rather than whichever arrived last.

  Bounds, enforced on every merge, oldest-reported first:

    * variants unreported for 30 days expire;
    * at most 8 variants per metric and 50,000 metrics;
    * help text over 4 KiB or names over 1 KiB are dropped;
    * the encoded set stays under 8 MiB.

  `record/2` publishes before the request that carried the metadata is
  acknowledged; storage adapters make that publication durable (S3 merges a
  per-tenant object with conditional writes) and skip it when every entry is
  already published for the day. Reads reflect other instances' writes after
  at most the adapter's read cache interval.
  """

  alias Pulse.Storage

  @expiry_days 30
  @max_variants 8
  @max_metrics 50_000
  @max_help 4096
  @max_name 1024
  @max_bytes 8 * 1024 * 1024

  @type entry :: {metric :: String.t(), type :: String.t(), help :: String.t(), unit :: String.t()}
  @type variant :: {String.t(), String.t(), String.t()}
  @type set :: %{optional(String.t()) => %{optional(variant()) => day :: integer()}}

  @doc "Publish `entries` for `tenant`, durably before returning `:ok`."
  @spec record(String.t(), [entry()]) :: :ok | {:error, term()}
  def record(_tenant, []), do: :ok

  def record(tenant, entries) do
    entries =
      entries
      |> Enum.filter(fn {metric, _type, help, unit} ->
        byte_size(metric) in 1..@max_name and byte_size(help) <= @max_help and byte_size(unit) <= @max_name
      end)
      |> Enum.map(fn {metric, type, help, unit} ->
        {:binary.copy(metric), type, :binary.copy(help), :binary.copy(unit)}
      end)
      |> Enum.uniq()

    if entries == [], do: :ok, else: Storage.put_metric_metadata(tenant, entries, today())
  end

  @doc """
  Prometheus `/api/v1/metadata` data: metric => variants, most recently
  reported first. `limit` bounds metrics and `limit_per_metric` variants;
  negative or nil means no limit, as in Prometheus.
  """
  @spec query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(tenant, opts \\ []) do
    with {:ok, set} <- Storage.metric_metadata(tenant), do: {:ok, view(set, today(), opts)}
  end

  @doc false
  @spec view(set(), integer(), keyword()) :: map()
  def view(set, today, opts) do
    metric = opts[:metric]
    per_metric = limit(opts[:limit_per_metric])

    set
    |> then(&if(metric, do: Map.take(&1, [metric]), else: &1))
    |> Enum.map(fn {name, variants} -> {name, live(variants, today)} end)
    |> Enum.reject(fn {_name, variants} -> variants == [] end)
    |> Enum.sort()
    |> Enum.take(limit(opts[:limit]))
    |> Map.new(fn {name, variants} ->
      {name, variants |> Enum.take(per_metric) |> Enum.map(&variant_json/1)}
    end)
  end

  defp limit(n) when is_integer(n) and n >= 0, do: n
  defp limit(_), do: 1_000_000_000

  # Unexpired variants, most recently reported first.
  defp live(variants, today) do
    variants
    |> Enum.filter(fn {_variant, day} -> day > today - @expiry_days end)
    |> Enum.sort_by(fn {variant, day} -> {-day, variant} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp variant_json({type, help, unit}), do: %{"type" => type, "help" => help, "unit" => unit}

  @doc "Whether merging `entries` on `today` changes `set`."
  @spec changed?(set(), [entry()], integer()) :: boolean()
  def changed?(set, entries, today) do
    Enum.any?(entries, fn {metric, type, help, unit} ->
      get_in(set, [metric, {type, help, unit}]) != today
    end)
  end

  @doc "Merge `entries` reported on `today` into `set`, then apply expiry and bounds."
  @spec merge(set(), [entry()], integer()) :: set()
  def merge(set, entries, today) do
    entries
    |> Enum.reduce(set, fn {metric, type, help, unit}, acc ->
      Map.update(acc, metric, %{{type, help, unit} => today}, &Map.put(&1, {type, help, unit}, today))
    end)
    |> Map.new(fn {metric, variants} -> {metric, bound_variants(variants, today)} end)
    |> Map.reject(fn {_metric, variants} -> variants == %{} end)
    |> bound_metrics()
    |> bound_bytes()
  end

  defp bound_variants(variants, today) do
    variants
    |> Enum.filter(fn {_variant, day} -> day > today - @expiry_days end)
    |> Enum.sort_by(fn {variant, day} -> {-day, variant} end)
    |> Enum.take(@max_variants)
    |> Map.new()
  end

  defp bound_metrics(set) when map_size(set) <= @max_metrics, do: set

  defp bound_metrics(set) do
    set
    |> Enum.sort_by(fn {metric, variants} -> {-Enum.max(Map.values(variants)), metric} end)
    |> Enum.take(@max_metrics)
    |> Map.new()
  end

  defp bound_bytes(set) do
    if byte_size(encode(set)) <= @max_bytes do
      set
    else
      # Retain the same newest suffix as oldest-first eviction, but encode each
      # metric only once instead of re-encoding the entire set for every eviction.
      empty_bytes = byte_size(encode(%{}))

      set
      |> Enum.sort_by(fn {metric, variants} -> {Enum.max(Map.values(variants)), metric} end, :desc)
      |> Enum.reduce_while({%{}, empty_bytes}, &retain_metric(&1, &2, empty_bytes))
      |> elem(0)
    end
  end

  defp retain_metric({metric, variants}, {kept, bytes}, empty_bytes) do
    separator = if map_size(kept) == 0, do: 0, else: 1
    bytes = bytes + byte_size(encode(%{metric => variants})) - empty_bytes + separator

    if bytes <= @max_bytes,
      do: {:cont, {Map.put(kept, metric, variants), bytes}},
      else: {:halt, {kept, bytes}}
  end

  @doc false
  def max_bytes, do: @max_bytes

  @doc ~s(The stored form: `{"v":1,"m":{metric:[[type,help,unit,day],...]}}`.)
  @spec encode(set()) :: binary()
  def encode(set) do
    metrics =
      Map.new(set, fn {metric, variants} ->
        {metric, Enum.map(variants, fn {{type, help, unit}, day} -> [type, help, unit, day] end)}
      end)

    Pulse.JSON.encode!(%{"v" => 1, "m" => metrics})
  end

  @spec decode(binary()) :: {:ok, set()} | {:error, :invalid_metric_metadata}
  def decode(binary) do
    with {:ok, %{"v" => 1, "m" => metrics}} when is_map(metrics) <- Pulse.JSON.decode(binary),
         {:ok, set} <- decode_metrics(Pulse.JSON.detach(metrics)) do
      {:ok, set}
    else
      _ -> {:error, :invalid_metric_metadata}
    end
  end

  defp decode_metrics(metrics) do
    Enum.reduce_while(metrics, {:ok, %{}}, fn {metric, variants}, {:ok, acc} ->
      if is_list(variants) and Enum.all?(variants, &valid_variant?/1) do
        {:cont, {:ok, Map.put(acc, metric, Map.new(variants, fn [t, h, u, d] -> {{t, h, u}, d} end))}}
      else
        {:halt, :error}
      end
    end)
  end

  defp valid_variant?([type, help, unit, day]),
    do: is_binary(type) and is_binary(help) and is_binary(unit) and is_integer(day)

  defp valid_variant?(_), do: false

  @doc false
  def today, do: div(System.os_time(:second), 86_400)
end
