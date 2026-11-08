defmodule Pulse.RemoteWrite.Push do
  @moduledoc """
  Decode a Prometheus remote_write body (v1 `WriteRequest` or Remote Write
  2.0 `io.prometheus.write.v2.Request`) into `[%Pulse.Record.MetricSample{}]`.

  The on-wire body is **Snappy-compressed** (block format, not frame)
  protobuf, with `Content-Type: application/x-protobuf` and
  `Content-Encoding: snappy`. The Rust NIF (`Pulse.Codec.NIF.decode_remote_write`)
  decompresses, parses the protobuf, computes a Prometheus-compatible
  `StableHash` fingerprint per series, and returns series envelopes carrying
  labels, samples, histograms and exemplars. V1 points are `{ts_ms, value}`;
  v2 points add a third `start_timestamp_ms | nil` element. Both timestamps
  use wire **milliseconds**. This module expands points into `%MetricSample{}`
  structs, rescaling only sample time to `timestamp_ns`, never source starts.

  Semantic errors inside a series (invalid labels, out-of-range
  timestamp) are counted in `rejected` rather than failing the whole
  request — the same contract as `Pulse.Loki.Push`. Native histograms become
  samples with `histogram` set (`Pulse.Record.NativeHistogram`); invalid ones
  count as rejected. Each exemplar is stored on its series' sample nearest to
  it in time, keeping its own timestamp; invalid exemplars are dropped, as in
  Prometheus.
  Stale markers and IEEE-754 non-finite values are preserved using a closed
  atom vocabulary rather than unsupported Erlang floats. A wire-level
  corruption fails the whole request with a typed error.
  """

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample

  @doc """
  Decode a Snappy-compressed `WriteRequest` protobuf body into
  `{:ok, samples, rejected}` or `{:error, reason}` where `reason` is one
  of `:invalid_snappy | :invalid_protobuf | :payload_too_large |
  :too_many_records | :attributes_too_large`.
  """
  @spec decode_protobuf(binary(), pos_integer()) ::
          {:ok, [MetricSample.t()], non_neg_integer()} | {:error, atom()}
  def decode_protobuf(body, max_decompressed) when is_binary(body) and is_integer(max_decompressed) do
    with {:ok, samples, rejected, _metadata} <- decode_with_metadata(body, max_decompressed),
         do: {:ok, samples, rejected}
  end

  @doc """
  Like `decode_protobuf/2`, also returning the request's metric metadata as
  `{metric, type, help, unit}` entries (`Pulse.MetricMetadata`). `version`
  selects the message: `:v1` (`prometheus.WriteRequest`) or `:v2` (Remote
  Write 2.0 `io.prometheus.write.v2.Request`, labels and metadata resolved
  through its symbol table, metadata attached per series).
  """
  @spec decode_with_metadata(binary(), pos_integer(), :v1 | :v2) ::
          {:ok, [MetricSample.t()], non_neg_integer(), [Pulse.MetricMetadata.entry()]} | {:error, atom()}
  def decode_with_metadata(body, max_decompressed, version \\ :v1)
      when is_binary(body) and is_integer(max_decompressed) do
    limits = Pulse.IngestLimits.native_options()

    decoded =
      case version do
        :v1 -> NIF.decode_remote_write_limited(body, max_decompressed, limits)
        :v2 -> NIF.decode_remote_write_v2_limited(body, max_decompressed, limits)
      end

    case decoded do
      {:ok, series, rejected, metadata} ->
        samples = series |> merge_series() |> Enum.flat_map(&expand_series/1)
        {:ok, samples, rejected, metadata}

      {:error, reason} when is_atom(reason) ->
        {:error, reason}
    end
  end

  # Senders send a series' samples, histograms and exemplars in separate
  # entries; join entries with the same labels so exemplars find samples.
  defp merge_series(series) do
    series
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn
      {_labels, [single]} ->
        single

      {labels, [{_, _, series_id, _, _} | _] = entries} ->
        {labels, Enum.flat_map(entries, &elem(&1, 1)), series_id, Enum.flat_map(entries, &elem(&1, 3)),
         Enum.flat_map(entries, &elem(&1, 4))}
    end)
  end

  # Each series: `{labels_map, samples, series_id, histograms, exemplars}`.
  # Samples/histograms have timestamp/value pairs (v1) or timestamp/value/start triples (v2).
  # Fan out one `%MetricSample{}` per sample or histogram. The label map is
  # shared across samples in the same series — Elixir maps are immutable so
  # the per-sample struct holds a reference to the one allocation.
  defp expand_series({labels, samples, series_id, histograms, exemplars})
       when is_map(labels) and is_list(samples) and is_integer(series_id) do
    floats = Enum.map(samples, &expand_sample(&1, labels, series_id, :value))

    # Remote write appends floats before histograms. A same-request float at
    # the same series/time wins, rather than storing both and letting query
    # conflict resolution replace it with the histogram. Admission and native
    # validation have already charged every supplied point, including losers.
    histograms =
      if samples == [] or histograms == [] do
        histograms
      else
        float_times = MapSet.new(samples, &elem(&1, 0))
        Enum.reject(histograms, &MapSet.member?(float_times, elem(&1, 0)))
      end

    natives = Enum.map(histograms, &expand_sample(&1, labels, series_id, :histogram))

    case floats ++ natives do
      # The series' samples arrived in another request: keep the exemplars on
      # a row without a value, which queries skip.
      [] ->
        exemplars = Enum.sort_by(exemplars, & &1.timestamp_ns)

        [
          %MetricSample{
            series_id: series_id,
            timestamp_ns: hd(exemplars).timestamp_ns,
            labels: labels,
            exemplars: exemplars
          }
        ]

      samples ->
        attach_exemplars(samples, exemplars)
    end
  end

  defp expand_sample({ts_ms, value}, labels, series_id, field), do: sample(labels, series_id, ts_ms, [{field, value}])

  defp expand_sample({ts_ms, value, start}, labels, series_id, field),
    do: sample(labels, series_id, ts_ms, [{field, value}, {:start_timestamp_ms, start}])

  defp sample(labels, series_id, ts_ms, fields),
    do: struct!(MetricSample, [series_id: series_id, timestamp_ns: ts_ms * 1_000_000, labels: labels] ++ fields)

  # Every sample of a series has its labels, so an exemplar goes to the one
  # nearest in time (the earlier one on ties).
  defp attach_exemplars(samples, []), do: samples

  defp attach_exemplars(samples, exemplars) do
    indexed = samples |> Enum.sort_by(& &1.timestamp_ns) |> Enum.with_index()

    hosts =
      Enum.group_by(exemplars, fn exemplar ->
        indexed
        |> Enum.min_by(fn {sample, i} -> {abs(sample.timestamp_ns - exemplar.timestamp_ns), i} end)
        |> elem(1)
      end)

    Enum.map(indexed, fn {sample, i} ->
      case Map.fetch(hosts, i) do
        {:ok, attached} -> %{sample | exemplars: Enum.sort_by(attached, & &1.timestamp_ns)}
        :error -> sample
      end
    end)
  end
end
