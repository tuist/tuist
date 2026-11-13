defmodule Pulse.Test.NativeQueryStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Codec.NIF
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3

  def append(signal, tenant, records, opts), do: Memory.append(signal, tenant, records, opts)

  def query(:logs, tenant, opts) do
    with {:ok, records} <- Memory.query(:logs, tenant, []),
         {:ok, blob, _, _, _} <- NIF.encode_log_segment_parquet(records) do
      NIF.decode_log_segment_parquet(
        blob,
        opts[:start_ts],
        opts[:end_ts],
        opts[:service],
        Keyword.get(opts, :matchers, []),
        Keyword.get(opts, :line_filters, [])
      )
    end
  end

  def query(:traces, tenant, opts) do
    with {:ok, spans} <- Memory.query(:traces, tenant, []),
         {:ok, blob, _, _} <- S3.encode_segment(:traces, spans) do
      S3.decode_segment(:traces, blob, opts[:start_ts], opts[:end_ts], opts)
    end
  end

  def query(:metrics, tenant, opts) do
    with {:ok, samples} <- Memory.query(:metrics, tenant, []),
         {:ok, blob, _, _, _} <- NIF.encode_metric_segment_parquet(samples) do
      NIF.decode_metric_segment_parquet(blob, opts[:start_ts], opts[:end_ts], Keyword.get(opts, :matchers, []))
    end
  end

  # Native LogQL range scans over the stored records, split into several
  # Parquet segments so accumulation across sources is exercised. Each
  # completed native scan is reported to the caller.
  def log_metric_scan(tenant, opts, scan) do
    {:ok, records} = Memory.query(:logs, tenant, [])

    records
    |> Enum.chunk_every(max(1, div(length(records), 3) + 1))
    |> Enum.reduce_while({:ok, {0, 0}}, fn chunk, {:ok, {selected, kept}} ->
      {:ok, blob, _, _, _} = NIF.encode_log_segment_parquet(chunk)

      case NIF.log_metric_scan_add(
             scan,
             blob,
             opts[:start_ts],
             opts[:end_ts],
             opts[:service],
             Keyword.get(opts, :matchers, []),
             Keyword.get(opts, :line_filters, [])
           ) do
        {:ok, {s, k}} -> {:cont, {:ok, {selected + s, kept + k}}}
        {:error, _} = error -> {:halt, error}
        :fallback -> {:halt, {:error, :native_fallback}}
      end
    end)
    |> tap(fn result -> if match?({:ok, _}, result), do: send(self(), :native_log_metric_scan) end)
  end
end
