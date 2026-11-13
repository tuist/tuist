defmodule PulseWeb.LokiController do
  use PulseWeb, :controller

  alias Pulse.Auth
  alias Pulse.Loki.Push

  @default_tenant "default"

  # Cap on the decompressed protobuf body. Loki's default upstream limit
  # is a few MiB per push; 16 MiB is comfortably above that and small
  # enough that a single misconfigured or malicious sender cannot
  # exhaust the request process's heap. The NIF checks it against the
  # length varint in the Snappy block header before allocating any
  # output buffer, and decompression fails if the payload does not
  # produce exactly that many bytes.
  @max_decompressed_bytes 16 * 1024 * 1024

  # Hard cap on the compressed body read off the socket. Set well
  # above @max_decompressed_bytes / 32× (a plausible upper bound for
  # protobuf-in-snappy ratios) so a legitimate 16 MiB uncompressed
  # payload always fits, and low enough that a runaway sender cannot
  # buffer arbitrary amounts of memory before we see the length header.
  @max_compressed_bytes 4 * 1024 * 1024

  @doc """
  Loki push receiver at `POST /loki/api/v1/push`.

  Accepts two wire formats:

    * `application/json` — the JSON push, optionally with
      `Content-Encoding: gzip`. Gzip is unwrapped by
      `PulseWeb.CompressedBodyReader` before `Plug.Parsers` runs, and
      the parsed map lands here as `params`.

    * `application/x-protobuf` — Alloy and Promtail's default. The body
      is a Snappy-compressed (raw block format) protobuf `PushRequest`.
      `Content-Encoding: snappy` and an absent content-encoding both
      mean "snappy" per the Loki convention; gzip/deflate over
      protobuf is rejected with 415.

  Tenant, auth, and idempotency semantics match the OTLP receiver:
  tenant from `X-Scope-OrgID` (default `"default"`), verified via
  `Pulse.Auth`, and `Idempotency-Key` propagated to the storage backend
  so a retry does not duplicate.

  On success the response is `204 No Content` per the Loki push
  convention — no body, no partial-success envelope. If any records
  were rejected during decoding, the count is surfaced in the
  `X-Pulse-Rejected-Records` response header so senders that want to
  monitor decode drops can, without breaking clients that expect a
  bodyless 204.
  """
  @tenant_regex ~r/\A[A-Za-z0-9_.\-]{1,128}\z/

  def push(conn, params) do
    tenant = tenant_from(conn)
    opts = append_opts(conn)

    with :ok <- validate_tenant(tenant),
         :ok <- Auth.verify(conn, tenant, :ingest) do
      case decode_body(conn, params) do
        {:ok, records, rejected, conn} -> finish(conn, tenant, opts, {:ok, records, rejected})
        {:error, reason, conn} -> finish(conn, tenant, opts, {:error, reason, conn})
      end
    else
      {:error, _} = error -> finish(conn, tenant, opts, error)
    end
  end

  defp finish(conn, tenant, opts, decoded) do
    with {:ok, records, rejected} <- decoded,
         :ok <- Pulse.Metrics.append(:logs, tenant, records, rejected, opts) do
      conn
      |> put_rejected_header(rejected)
      |> send_resp(:no_content, "")
    else
      {:error, :unsupported_content_type, conn} ->
        conn
        |> put_status(:unsupported_media_type)
        |> json(%{error: "unsupported_content_type"})

      {:error, :invalid_snappy, conn} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_snappy"})

      {:error, :invalid_protobuf, conn} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_protobuf"})

      {:error, :payload_too_large, conn} ->
        conn
        |> put_status(:request_entity_too_large)
        |> json(%{error: "payload_too_large"})

      {:error, reason, conn} when reason in [:too_many_records, :attributes_too_large] ->
        conn
        |> put_status(:request_entity_too_large)
        |> json(%{error: to_string(reason)})

      {:error, {:invalid_tenant, _}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_tenant"})

      {:error, reason} when reason in [:missing_token, :invalid_token, :unknown_tenant] ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: to_string(reason)})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :auth_unavailable} ->
        conn
        |> put_resp_header("retry-after", "5")
        |> put_status(:service_unavailable)
        |> json(%{error: "auth_unavailable"})

      {:error, :keyed_content_mismatch} ->
        conn |> put_status(:conflict) |> json(%{error: "keyed_content_mismatch"})

      {:error, {:encode_failed, _}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "encode_failed"})

      {:error, {:attribute_key_collision, _}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "attribute_key_collision"})

      {:error, reason} when reason in [:retention_expired, :timestamp_too_new] ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})

      {:error, reason}
      when reason in [
             :retention_capacity,
             :metadata_scan_limit,
             :retention_policy_mismatch,
             :retention_migration_required,
             :managed_manifest_missing,
             :manifest_page_missing,
             :cas_retries_exhausted
           ] ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: to_string(reason)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  # Content-type dispatch. `Plug.Parsers` already handled JSON (and its
  # gzip variant via CompressedBodyReader) — for that path the map is
  # already in `params`. Protobuf is not parsed by Plug.Parsers, so its
  # bytes are still on the socket and we read them here.
  defp decode_body(conn, params) do
    case content_type(conn) do
      :json ->
        case Pulse.IngestLimits.validate(:loki, params) do
          :ok ->
            {records, rejected} = decode_json(params)
            {:ok, records, rejected, conn}

          {:error, reason} ->
            {:error, reason, conn}
        end

      :protobuf ->
        case validate_protobuf_encoding(conn) do
          :ok -> decode_protobuf(conn)
          {:error, reason} -> {:error, reason, conn}
        end

      :unsupported ->
        {:error, :unsupported_content_type, conn}
    end
  end

  defp decode_json(params), do: Pulse.Metrics.time_stage(:logs, :decode, fn -> Push.decode(params) end)

  defp decode_protobuf(conn) do
    case read_full_body(conn) do
      {:ok, body, conn} ->
        decoded =
          Pulse.Metrics.time_stage(:logs, :decode, fn -> Push.decode_protobuf(body, @max_decompressed_bytes) end)

        case decoded do
          {:ok, records, rejected} -> {:ok, records, rejected, conn}
          {:error, reason} -> {:error, reason, conn}
        end

      {:error, reason, conn} ->
        {:error, reason, conn}

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  # JSON when the header is absent — Plug.Parsers picks its parser off
  # the header, and with none we treat the request as JSON to match
  # the pre-existing behavior.
  defp content_type(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [] ->
        :json

      [ct | _] ->
        cond do
          json_content_type?(ct) -> :json
          protobuf_content_type?(ct) -> :protobuf
          true -> :unsupported
        end
    end
  end

  defp json_content_type?(ct) do
    ct
    |> String.downcase()
    |> String.starts_with?("application/json")
  end

  defp protobuf_content_type?(ct) do
    ct
    |> String.downcase()
    |> String.starts_with?("application/x-protobuf")
  end

  # Loki's protobuf path treats both `Content-Encoding: snappy` and an
  # absent content-encoding as snappy. Gzip and deflate are declared
  # unsupported: we could add them, but Alloy never sends them, and
  # returning 415 makes the "missing feature" case explicit rather than
  # letting an unexpected encoding surface as an invalid_snappy 400.
  defp validate_protobuf_encoding(conn) do
    case Plug.Conn.get_req_header(conn, "content-encoding") do
      [] -> :ok
      [enc] -> if String.downcase(enc) == "snappy", do: :ok, else: :unsupported_content_type
      _ -> :unsupported_content_type
    end
    |> case do
      :ok -> :ok
      :unsupported_content_type -> {:error, :unsupported_content_type}
    end
  end

  defp read_full_body(conn) do
    case Plug.Conn.read_body(conn, length: @max_compressed_bytes) do
      {:ok, body, conn} ->
        {:ok, body, conn}

      {:more, _chunk, conn} ->
        # Plug returns `:more` only when a single read filled its
        # `length` window — i.e. the compressed body is above our cap.
        # A snappy-compressed Loki push above this cap has no
        # legitimate shape, so refuse rather than buffer arbitrary
        # amounts.
        {:error, :payload_too_large, conn}

      {:error, _} = err ->
        err
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
