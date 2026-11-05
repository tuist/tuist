defmodule Pulse.OTLP.Ingest do
  @moduledoc """
  Transport-independent OTLP export handling, shared by OTLP/HTTP and
  OTLP/gRPC: preparation and storage of decoded records, and the outcome
  classification both transports map to their own status codes.

  `decoded` is a signal decoder's result: `{:ok, records, rejected}` or
  `{:error, reason}`. An idempotency key makes the request keyed, which
  rejects partially valid batches instead of acknowledging a subset.
  """

  alias Pulse.OTLP.Logs
  alias Pulse.OTLP.Metrics
  alias Pulse.OTLP.Rejections
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.S3

  @type signal :: :logs | :metrics | :traces
  @type status :: 400 | 401 | 409 | 413 | 415 | 429 | 503

  @spec ingest(signal(), String.t(), String.t() | nil, tuple()) ::
          {:ok, non_neg_integer(), String.t()} | {:error, term()}
  def ingest(:logs, tenant, key, decoded) do
    with {:ok, records, rejected} <- decoded,
         :ok <- keyed_records(key, rejected, :invalid_otlp),
         {:ok, records} <- Pulse.Metrics.time_stage(:logs, :prepare, fn -> Logs.prepare(records, key) end),
         :ok <- append(:logs, tenant, records, rejected, key_opts(key)),
         do: {:ok, rejected, Rejections.message(%{})}
  end

  def ingest(:metrics, tenant, key, decoded) do
    with {:ok, samples, rejected} <- decoded,
         :ok <- keyed_records(key, rejected, :invalid_otlp),
         :ok <- append(:metrics, tenant, samples, rejected, key_opts(key)),
         do: {:ok, rejected, Rejections.message(%{})}
  end

  def ingest(:traces, tenant, key, {:ok, spans, rejected}),
    do: ingest(:traces, tenant, key, {:ok, spans, rejected, %{}})

  def ingest(:traces, tenant, key, decoded) do
    opts = key_opts(key)

    with {:ok, spans, rejected, rejections} <- decoded,
         :ok <- Rejections.record(:traces, tenant, rejections),
         :ok <- keyed_records(key, rejected, :invalid_keyed_batch),
         {:ok, spans, rejected, rejections} <-
           Pulse.Metrics.time_stage(:traces, :prepare, fn ->
             retained_spans(opts, tenant, spans, rejected, rejections)
           end),
         :ok <- append(:traces, tenant, spans, rejected, opts),
         do: {:ok, rejected, Rejections.message(rejections)}
  end

  @doc "Decode one export for `signal`, keeping per-record rejection reasons where the decoder has them."
  def decode(signal, format, input),
    do: Pulse.Metrics.time_stage(signal, :decode, fn -> do_decode(signal, format, input) end)

  defp do_decode(:traces, :json, input), do: Traces.decode_detailed(input)
  defp do_decode(:traces, :protobuf, input), do: Traces.decode_protobuf_detailed(input)
  defp do_decode(signal, :json, input), do: decoder(signal).decode(input)
  defp do_decode(signal, :protobuf, input), do: decoder(signal).decode_protobuf(input)

  defp decoder(:logs), do: Logs
  defp decoder(:metrics), do: Metrics

  @doc "The partial-success field naming rejected items for a signal."
  @spec rejected_field(signal()) :: String.t()
  def rejected_field(:logs), do: "rejectedLogRecords"
  def rejected_field(:metrics), do: "rejectedDataPoints"
  def rejected_field(:traces), do: "rejectedSpans"

  @doc "Encoded `Export*ServiceResponse`: empty, or a partial success naming rejected items."
  @spec response_protobuf(non_neg_integer(), String.t()) :: binary()
  def response_protobuf(rejected, message \\ Rejections.message(%{}))
  def response_protobuf(0, _message), do: ""

  def response_protobuf(rejected, message) do
    partial = IO.iodata_to_binary([<<8>>, varint(rejected), field_bytes(2, message)])
    IO.iodata_to_binary(field_bytes(1, partial))
  end

  @doc false
  def field_bytes(field, value), do: [varint(field * 8 + 2), varint(byte_size(value)), value]

  @doc false
  def varint(n) when n < 128, do: <<n>>
  def varint(n), do: [<<Bitwise.bor(Bitwise.band(n, 127), 128)>>, varint(Bitwise.bsr(n, 7))]

  @doc """
  HTTP-style status and message for a failed export. 429 and 503 are
  retryable; transports should advertise a retry delay for them.
  """
  @spec classify(signal(), term()) :: {status(), String.t()}
  def classify(_signal, :ambiguous_header), do: {400, "tenant and idempotency headers must not be repeated"}
  def classify(:traces, {:invalid_tenant, _}), do: {400, "invalid tenant"}
  def classify(_signal, {:invalid_tenant, _}), do: {400, "invalid_tenant"}

  def classify(:traces, reason) when reason in [:missing_token, :invalid_token, :unknown_tenant],
    do: {401, "unauthorized"}

  def classify(_signal, reason) when reason in [:missing_token, :invalid_token, :unknown_tenant],
    do: {401, Atom.to_string(reason)}

  def classify(_signal, :forbidden), do: {403, "forbidden"}
  def classify(_signal, :auth_unavailable), do: {503, "auth_unavailable"}

  def classify(:traces, reason) when reason in [:unsupported_content_type, :unsupported_content_encoding],
    do: {415, "unsupported media type or encoding"}

  def classify(_signal, reason) when reason in [:unsupported_content_type, :unsupported_content_encoding],
    do: {415, Atom.to_string(reason)}

  def classify(_signal, reason) when reason in [:payload_too_large, :too_many_records, :attributes_too_large],
    do: {413, Atom.to_string(reason)}

  def classify(:traces, :too_many_trace_nodes), do: {413, "too_many_trace_nodes"}
  def classify(signal, :too_many_otlp_nodes) when signal in [:logs, :metrics], do: {413, "too_many_otlp_nodes"}
  def classify(_signal, :owner_overloaded), do: {429, "ingest capacity exhausted"}
  def classify(_signal, :rate_limited), do: {429, "tenant ingest quota exceeded"}

  def classify(_signal, reason)
      when reason in [:invalid_otlp, :invalid_protobuf, :invalid_gzip, :retention_expired, :timestamp_too_new],
      do: {400, Atom.to_string(reason)}

  def classify(:logs, :missing_keyed_timestamp), do: {400, "missing_keyed_timestamp"}

  def classify(:traces, reason) when reason in [:invalid_keyed_batch, :trace_projection_invalid],
    do: {400, Atom.to_string(reason)}

  def classify(_signal, :keyed_content_mismatch), do: {409, "keyed_content_mismatch"}
  def classify(signal, {:encode_failed, _}), do: {400, "invalid #{noun(signal)}"}
  def classify(:logs, {:attribute_key_collision, _}), do: {400, "invalid attributes"}

  def classify(:logs, reason)
      when reason in [
             :retention_capacity,
             :metadata_scan_limit,
             :retention_policy_mismatch,
             :retention_migration_required
           ], do: {503, Atom.to_string(reason)}

  def classify(:traces, _reason), do: {503, "trace storage unavailable"}
  def classify(signal, _reason), do: {503, "#{signal_name(signal)} storage unavailable"}

  defp noun(:logs), do: "logs"
  defp noun(:metrics), do: "metrics"
  defp noun(:traces), do: "spans"

  defp signal_name(:logs), do: "log"
  defp signal_name(:metrics), do: "metric"

  defp key_opts(nil), do: []
  defp key_opts(key), do: [idempotency_key: key]

  defp keyed_records(nil, _rejected, _reason), do: :ok
  defp keyed_records(_key, 0, _reason), do: :ok
  defp keyed_records(_key, _rejected, reason), do: {:error, reason}

  defp append(signal, tenant, records, rejected, opts) do
    case Pulse.Metrics.append(signal, tenant, records, rejected, opts) do
      # A refreshed floor must not discard fresh siblings of an unkeyed
      # coalesced request. Retry and prefilter again; never rewrite a keyed one.
      {:error, :retention_expired} when signal == :traces and opts == [] -> {:error, :retention_floor_advanced}
      result -> result
    end
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  defp expired(_tenant, retained, rejected, rejections, 0), do: {:ok, retained, rejected, rejections}

  defp expired(tenant, retained, rejected, rejections, expired) do
    expiry = %{{:retention_expired, nil} => expired}
    :ok = Rejections.record(:traces, tenant, expiry)
    {:ok, retained, rejected + expired, Map.merge(rejections, expiry, fn _, a, b -> a + b end)}
  end

  defp retained_spans(opts, tenant, spans, rejected, rejections) do
    if spans != [] and Storage.adapter() == S3 and opts == [] do
      with {:ok, retained, expired} <- S3.retained_traces(tenant, spans),
           do: expired(tenant, retained, rejected, rejections, expired)
    else
      {:ok, spans, rejected, rejections}
    end
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end
end
