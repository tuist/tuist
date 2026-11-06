defmodule PulseWeb.RemoteWriteController do
  use PulseWeb, :controller

  alias Pulse.Auth
  alias Pulse.RemoteWrite.Push

  @default_tenant "default"
  @tenant_regex ~r/\A[A-Za-z0-9_.\-]{1,128}\z/

  # Cap on the decompressed protobuf body. Prometheus's upstream
  # `remote_write` server defaults to a few MiB; 16 MiB sits comfortably
  # above that and small enough that a single misconfigured or malicious
  # sender cannot exhaust the request process's heap. The NIF checks it
  # against the length varint in the Snappy block header before
  # allocating any output buffer.
  @max_decompressed_bytes 16 * 1024 * 1024

  # Hard cap on the compressed body read off the socket.
  @max_compressed_bytes 4 * 1024 * 1024

  @doc """
  Prometheus Remote Write receiver at `POST /api/v1/write`, for both 1.0
  (`prometheus.WriteRequest`) and 2.0 (`io.prometheus.write.v2.Request`).

  Protocol contract (what Alloy / Grafana Agent / vanilla Prometheus
  will send unmodified):

    * `Content-Type: application/x-protobuf` (required, 415 otherwise). Its
      `proto` parameter selects the message: absent or
      `prometheus.WriteRequest` is 1.0, `io.prometheus.write.v2.Request` is
      2.0, anything else is 415.
    * `Content-Encoding: snappy` (required, 415 otherwise — the
      Prometheus spec is stricter than Loki's push here: an absent
      content-encoding is NOT treated as snappy).
    * `X-Prometheus-Remote-Write-Version` (advisory: missing, `0.*`, `1.*`
      and `2.*` are accepted; another major is rejected with 400).
    * `X-Scope-OrgID: <tenant>` (optional; defaults to `"default"`).
    * `Idempotency-Key: <token>` (optional; propagated to storage).

  Status codes:

    * `204 No Content` on success; 5xx and optionally 429 are retryable,
      other 4xx are permanent.
    * `400` on invalid snappy, invalid protobuf, or invalid tenant name.
    * `401` on auth failures.
    * `409` on existing keyed bytes differing (`keyed_content_mismatch`);
      preserve storage evidence rather than retrying or overwriting.
    * `413` if the body, record count, or attributes exceed ingest budgets.
    * `415` on wrong `Content-Type` or `Content-Encoding`.
    * `429` on storage backpressure (`:owner_overloaded`) — Prometheus
      interprets this as a retryable signal and backs off.
    * `503` on other transient storage failures.

  Rejected-sample count is surfaced in `X-Pulse-Rejected-Records` to
  mirror the Loki push convention.

  2.0 responses also carry `X-Prometheus-Remote-Write-{Samples,Histograms,Exemplars}-Written`.
  As in Prometheus's receiver, a 2.0 request with rejected series or invalid
  histograms stores what is valid and answers 400, so senders count the rest
  as failed instead of retrying it. Invalid exemplars are dropped and missing
  from the written count. A 1.0 request keeps answering 204 with the rejected
  count.
  """
  def write(conn, _params) do
    tenant = tenant_from(conn)
    opts = append_opts(conn)

    with :ok <- validate_tenant(tenant),
         :ok <- Auth.verify(conn, tenant, :ingest),
         {:ok, version} <- message_version(conn),
         :ok <- validate_content_encoding(conn),
         :ok <- validate_version_header(conn) do
      case read_full_body(conn) do
        {:ok, body, conn} ->
          finish(conn, tenant, opts, version, decode(body, version))

        {:error, reason, conn} ->
          finish(conn, tenant, opts, version, {:error, reason})

        {:error, _} = error ->
          finish(conn, tenant, opts, version, error)
      end
    else
      {:error, _} = error -> finish(conn, tenant, opts, :v1, error)
    end
  end

  defp decode(body, version),
    do:
      Pulse.Metrics.time_stage(:metrics, :decode, fn ->
        Push.decode_with_metadata(body, @max_decompressed_bytes, version)
      end)

  defp finish(conn, tenant, opts, version, decoded) do
    # Metadata publishes first: if it fails, nothing is stored and the
    # sender's retry of the whole request cannot duplicate samples.
    # Written counts are taken before append so a request waiting for durable
    # publication no longer retains its decoded samples (see IngestAdmission).
    with {:ok, samples, rejected, metadata} <- decoded,
         written = written_counts(version, samples),
         :ok <- Pulse.Metrics.time_stage(:metrics, :prepare, fn -> Pulse.MetricMetadata.record(tenant, metadata) end),
         :ok <- append_samples(tenant, samples, rejected, opts) do
      conn
      |> put_rejected_header(rejected)
      |> put_written_headers(written)
      |> written(version, rejected)
    else
      {:error, :unsupported_content_type} ->
        conn |> put_status(:unsupported_media_type) |> json(%{error: "unsupported_content_type"})

      {:error, :unsupported_content_encoding} ->
        conn |> put_status(:unsupported_media_type) |> json(%{error: "unsupported_content_encoding"})

      {:error, :unsupported_remote_write_version} ->
        conn |> put_status(:bad_request) |> json(%{error: "unsupported_remote_write_version"})

      {:error, :invalid_snappy} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_snappy"})

      {:error, :invalid_protobuf} ->
        conn
        |> put_written_headers(written_counts(version, []))
        |> put_status(:bad_request)
        |> json(%{error: "invalid_protobuf"})

      {:error, :payload_too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "payload_too_large"})

      {:error, reason} when reason in [:too_many_records, :attributes_too_large] ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: to_string(reason)})

      {:error, {:invalid_tenant, _}} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_tenant"})

      {:error, reason} when reason in [:missing_token, :invalid_token, :unknown_tenant] ->
        conn |> put_status(:unauthorized) |> json(%{error: to_string(reason)})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :auth_unavailable} ->
        conn
        |> put_resp_header("retry-after", "5")
        |> put_status(:service_unavailable)
        |> json(%{error: "auth_unavailable"})

      {:error, :owner_overloaded} ->
        # 429 — Prometheus retries on 5xx and 429 with backoff. The
        # typed `:owner_overloaded` from `ManifestOwner.register_segments`
        # is explicit backpressure, not a server fault, so 429 is the
        # right surface.
        conn |> put_status(:too_many_requests) |> json(%{error: "backpressure"})

      {:error, :keyed_content_mismatch} ->
        conn |> put_status(:conflict) |> json(%{error: "keyed_content_mismatch"})

      {:error, {:encode_failed, _}} ->
        conn |> put_status(:bad_request) |> json(%{error: "encode_failed"})

      {:error, {:decode_failed, _}} ->
        conn |> put_status(:bad_request) |> json(%{error: "decode_failed"})

      {:error, reason} when reason in [:retention_expired, :timestamp_too_new] ->
        conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})

      {:error, reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: inspect(reason)})
    end
  end

  defp written(conn, :v2, rejected) when rejected > 0 do
    conn |> put_status(:bad_request) |> json(%{error: "rejected_records", rejected: rejected})
  end

  defp written(conn, _version, _rejected), do: send_resp(conn, :no_content, "")

  # Remote Write 2.0 senders treat a 2xx without these as a 1.0-only receiver.
  defp written_counts(:v1, _samples), do: nil

  defp written_counts(:v2, samples) do
    {Enum.count(samples, &(not is_nil(&1.value))), Enum.count(samples, & &1.histogram),
     Enum.reduce(samples, 0, &(length(&1.exemplars || []) + &2))}
  end

  defp put_written_headers(conn, nil), do: conn

  defp put_written_headers(conn, {floats, histograms, exemplars}) do
    conn
    |> Plug.Conn.put_resp_header("x-prometheus-remote-write-samples-written", Integer.to_string(floats))
    |> Plug.Conn.put_resp_header("x-prometheus-remote-write-histograms-written", Integer.to_string(histograms))
    |> Plug.Conn.put_resp_header("x-prometheus-remote-write-exemplars-written", Integer.to_string(exemplars))
  end

  # Metadata-only requests (senders send metadata apart from samples) store no samples.
  defp append_samples(_tenant, [], 0, _opts), do: :ok

  defp append_samples(tenant, samples, rejected, opts),
    do: Pulse.Metrics.append(:metrics, tenant, samples, rejected, opts)

  # `application/x-protobuf[;proto=<message>]`, as both protocol versions send it.
  defp message_version(conn) do
    with [content_type | _] <- Plug.Conn.get_req_header(conn, "content-type"),
         [media | params] <- content_type |> String.split(";") |> Enum.map(&String.trim/1),
         "application/x-protobuf" <- String.downcase(media) do
      params
      |> Enum.find_value(&proto_param/1)
      |> case do
        nil -> {:ok, :v1}
        "prometheus.WriteRequest" -> {:ok, :v1}
        "io.prometheus.write.v2.Request" -> {:ok, :v2}
        _ -> {:error, :unsupported_content_type}
      end
    else
      _ -> {:error, :unsupported_content_type}
    end
  end

  defp proto_param(param) do
    case String.split(param, "=", parts: 2) do
      [key, value] -> if String.downcase(String.trim(key)) == "proto", do: value |> String.trim() |> String.trim("\"")
      _ -> nil
    end
  end

  # The Prometheus remote_write v1 spec requires `Content-Encoding: snappy`.
  # Unlike Loki's push, an absent header is NOT accepted — rejecting it
  # keeps us conformant and surfaces a misconfigured sender immediately.
  defp validate_content_encoding(conn) do
    case Plug.Conn.get_req_header(conn, "content-encoding") do
      [enc] -> if String.downcase(enc) == "snappy", do: :ok, else: {:error, :unsupported_content_encoding}
      _ -> {:error, :unsupported_content_encoding}
    end
  end

  # `X-Prometheus-Remote-Write-Version`: 1.0 senders send `0.1.0`, 2.0 senders
  # `2.0.0` (older forwarders omit it). The message type comes from the
  # Content-Type, so the header is advisory; an unknown major is refused
  # rather than risk mis-parsing a future wire shape.
  defp validate_version_header(conn) do
    case Plug.Conn.get_req_header(conn, "x-prometheus-remote-write-version") do
      [] ->
        :ok

      [v | _] ->
        if String.starts_with?(v, ["0.", "1.", "2."]), do: :ok, else: {:error, :unsupported_remote_write_version}
    end
  end

  defp read_full_body(conn) do
    case Plug.Conn.read_body(conn, length: @max_compressed_bytes) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _, conn} -> {:error, :payload_too_large, conn}
      {:error, _} = err -> err
    end
  end

  defp validate_tenant(tenant) do
    if Regex.match?(@tenant_regex, tenant),
      do: :ok,
      else: {:error, {:invalid_tenant, tenant}}
  end

  defp tenant_from(conn) do
    case Plug.Conn.get_req_header(conn, "x-scope-orgid") do
      [tenant | _] when is_binary(tenant) and tenant != "" -> tenant
      _ -> @default_tenant
    end
  end

  defp append_opts(conn) do
    case Plug.Conn.get_req_header(conn, "idempotency-key") do
      [key | _] when is_binary(key) and byte_size(key) > 0 -> [idempotency_key: key]
      _ -> []
    end
  end

  defp put_rejected_header(conn, 0), do: conn

  defp put_rejected_header(conn, rejected) do
    Plug.Conn.put_resp_header(conn, "x-pulse-rejected-records", Integer.to_string(rejected))
  end
end
