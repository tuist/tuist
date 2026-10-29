defmodule Tuist.Cargo.CacheMetrics do
  @moduledoc "Bounded aggregate Cargo cache measurements. Estimates are not wall-clock savings."

  alias Tuist.Cargo.CacheDetails

  @counters ~w(hits misses unconsulted verifications divergences prefetched_actions downloaded_bytes uploaded_bytes remote_failures background_upload_failures estimated_compiler_duration_avoided_ns prefetch_duration_ns materialization_duration_ns remote_action_lookup_duration_ns remote_blob_transfer_duration_ns upload_drain_duration_ns)a
  @maximum 9_000_000_000_000_000

  def counters, do: @counters
  def maximum, do: @maximum

  def encode(nil), do: {:ok, ""}

  def encode(%{version: 1} = metrics) do
    if map_size(metrics) <= length(@counters) + 2 and
         Enum.all?(Map.keys(metrics), &(&1 in [:version, :details | @counters])) and
         Enum.all?(@counters, &valid_counter?(metrics, &1)) do
      with {:ok, details} <- CacheDetails.normalize(metrics[:details]) do
        values = Map.take(metrics, [:version | @counters])
        {:ok, JSON.encode!(if(details, do: Map.put(values, :details, details), else: values))}
      end
    else
      {:error, :invalid_cache_metrics}
    end
  end

  def encode(_), do: {:error, :invalid_cache_metrics}

  defp valid_counter?(metrics, key) do
    value = Map.get(metrics, key, 0)
    is_integer(value) and value >= 0 and value <= @maximum
  end

  def read(%{cache_metrics: json}) when is_binary(json) and byte_size(json) in 1..4_100_000 do
    with {:ok, %{"version" => 1} = values} <- JSON.decode(json),
         metrics = Map.new([:version | @counters], &{&1, Map.get(values, Atom.to_string(&1), 0)}),
         {:ok, _} <- encode(metrics) do
      case CacheDetails.normalize(values["details"]) do
        {:ok, details} when not is_nil(details) -> Map.put(metrics, :details, details)
        _ -> metrics
      end
    else
      _ -> nil
    end
  end

  def read(_), do: nil

  def task_misses(metrics), do: Enum.sum(Enum.map([:misses, :unconsulted, :verifications], &Map.get(metrics, &1, 0)))

  def hit_rate(%{hits: hits} = metrics) do
    total = hits + task_misses(metrics)
    if total > 0, do: Float.round(100 * hits / total, 1)
  end

  def hit_rate(_), do: nil
end
