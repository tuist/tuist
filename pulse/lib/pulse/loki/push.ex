defmodule Pulse.Loki.Push do
  @moduledoc """
  Decode a Loki `POST /loki/api/v1/push` body into a flat list of
  `Pulse.Record.Log`.

  Two wire formats land here: the JSON push, decoded in Elixir by
  `decode/1`, and the Snappy-compressed protobuf push (Alloy's default),
  decoded in Rust by `decode_protobuf/2`. Both apply the same mapping
  into `Pulse.Record.Log`, described below, so a record looks identical
  whichever path it arrived on.

  ### JSON shape

      {
        "streams": [
          {
            "stream": { "service_name": "api", "level": "info" },
            "values": [
              [ "1700000000000000000", "hello" ],
              [ "1700000000000000001", "with meta", {"trace_id": "abc", "user_id": "u1"} ]
            ]
          }
        ]
      }

  ### Protobuf shape

  Loki's `PushRequest` → `Stream` → `Entry`. Labels arrive as a
  Prometheus-style `{k="v",...}` string with Go-quoted values;
  timestamps are `google.protobuf.Timestamp`-shaped (`{seconds, nanos}`);
  structured metadata is a repeated name/value pair.

  ## Mapping to Pulse.Record.Log

    * Stream labels populate `resource` — they identify the emitter and
      are constant across the stream, the same role resource attributes
      play in OTLP.
    * `service_name` (Grafana's OTel-aligned convention) or, as a
      fallback, `service`, is lifted to `Log.service`. It stays in
      `resource` too so a `resource.service_name` query still sees it.
    * `level` (or `detected_level`) is lifted to `Log.severity_text`.
    * Structured metadata is per-record — it populates `attributes`.
    * `trace_id` / `span_id` from structured metadata are lifted to the
      dedicated struct fields and removed from `attributes`, so a
      caller querying by trace id sees them in one canonical place
      regardless of which ingest path a record came in on.

  ## Return shape

  `{records, rejected}`, mirroring `Pulse.OTLP.Logs.decode/1`. `rejected`
  counts value tuples the decoder could not interpret (missing timestamp,
  non-string line, malformed shape). A whole-stream drop (e.g. `stream`
  is not a map, or a protobuf `labels` string is malformed) is counted
  as one reject per entry in that stream — the sender should still know
  that many records did not land.
  """

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log

  @doc """
  Decode a parsed JSON payload.

  Returns `{records, rejected}`. A payload that is not shaped like a
  Loki push request returns `{[], 0}` — there is nothing to count,
  because nothing was parseable in the first place.
  """
  @spec decode(map()) :: {[Log.t()], non_neg_integer()}
  def decode(%{"streams" => streams}) when is_list(streams) do
    streams
    |> Enum.reduce({[], 0}, fn stream, {records, rejected} ->
      {s_records, s_rejected} = decode_stream(stream)
      {[s_records | records], rejected + s_rejected}
    end)
    |> then(fn {records, rejected} ->
      {records |> Enum.reverse() |> List.flatten(), rejected}
    end)
  end

  def decode(_), do: {[], 0}

  @doc """
  Decode a Snappy-compressed (raw block format) protobuf `PushRequest`,
  the body Grafana Alloy and Promtail send by default.

  Decompression and decoding run in Rust (`Pulse.Codec.NIF`). The
  uncompressed size is read from the Snappy header and checked against
  `max_decompressed_bytes` before any output buffer is allocated.

  Returns `{:ok, records, rejected}` with the same record mapping and
  reject semantics as `decode/1`, plus one addition: a record whose line
  or structured metadata is not valid UTF-8 is rejected on its own
  instead of failing the batch. Wire-level corruption fails the whole
  request.

  Every string in the returned records is a sub-binary of the
  decompressed body. Records are expected to be request-scoped; anything
  that retains them long-term should `:binary.copy/1` the fields it keeps,
  or it will pin the whole buffer.
  """
  @spec decode_protobuf(binary(), pos_integer()) ::
          {:ok, [Log.t()], non_neg_integer()}
          | {:error,
             :invalid_snappy | :invalid_protobuf | :payload_too_large | :too_many_records | :attributes_too_large}
  def decode_protobuf(compressed, max_decompressed_bytes)
      when is_binary(compressed) and is_integer(max_decompressed_bytes) and max_decompressed_bytes > 0 do
    NIF.decode_loki_push_limited(compressed, max_decompressed_bytes, Pulse.IngestLimits.native_options())
  end

  defp decode_stream(%{"stream" => labels, "values" => values}) when is_map(labels) and is_list(values) do
    {service, severity_text, resource} = split_labels(labels)

    Enum.reduce(values, {[], 0}, fn value, {rs, rj} ->
      case decode_value(value, service, severity_text, resource) do
        {:ok, record} -> {[record | rs], rj}
        :error -> {rs, rj + 1}
      end
    end)
    |> then(fn {records, rejected} -> {Enum.reverse(records), rejected} end)
  end

  # Missing/malformed `stream` map: every value in this stream is a
  # reject, because we can't attribute records without labels.
  defp decode_stream(%{"values" => values}) when is_list(values), do: {[], length(values)}
  defp decode_stream(_), do: {[], 0}

  # Split stream labels into (service, severity_text, resource). The
  # resource map keeps *all* labels — including the lifted service and
  # level — so structured queries that filter on `resource.level` still
  # work, and so a caller looking at the stored record can see the raw
  # label set as sent.
  defp split_labels(labels) do
    service = labels["service_name"] || labels["service"]

    severity_text =
      case labels["level"] || labels["detected_level"] do
        nil -> nil
        v when is_binary(v) -> v
        v -> to_string(v)
      end

    {service, severity_text, labels}
  end

  defp decode_value([ts, line], service, severity_text, resource) when is_binary(line) do
    build_record(ts, line, %{}, service, severity_text, resource)
  end

  defp decode_value([ts, line, meta], service, severity_text, resource) when is_binary(line) and is_map(meta) do
    build_record(ts, line, meta, service, severity_text, resource)
  end

  defp decode_value(_, _, _, _), do: :error

  defp build_record(ts, line, meta, service, severity_text, resource) do
    with {:ok, ts_ns} <- parse_ts(ts) do
      {trace_id, span_id, attributes} = split_metadata(meta)

      {:ok,
       %Log{
         timestamp_ns: ts_ns,
         observed_timestamp_ns: nil,
         severity_number: nil,
         severity_text: severity_text,
         service: service,
         body: line,
         trace_id: trace_id,
         span_id: span_id,
         attributes: attributes,
         resource: resource
       }}
    end
  end

  # Loki's spec form is a decimal-string ns integer. Numeric forms show
  # up in a handful of client libraries, so accept them too. Anything
  # else is a reject; a record with no timestamp has no place in a
  # time-partitioned store.
  defp parse_ts(ts) when is_integer(ts) and ts >= 0, do: {:ok, ts}

  defp parse_ts(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_ts(_), do: :error

  # Structured metadata is a flat string map per the Loki spec. We lift
  # `trace_id` and `span_id` into their dedicated struct fields and
  # remove them from `attributes` so a caller has exactly one canonical
  # place to look. Every other key stays in `attributes`.
  defp split_metadata(meta) when is_map(meta) do
    trace_id = nil_if_blank(meta["trace_id"])
    span_id = nil_if_blank(meta["span_id"])
    attributes = meta |> Map.drop(["trace_id", "span_id"])
    {trace_id, span_id, attributes}
  end

  defp nil_if_blank(nil), do: nil
  defp nil_if_blank(""), do: nil
  defp nil_if_blank(v), do: v
end
