defmodule Condukt.Sandbox.NetworkPolicy.Request do
  @moduledoc """
  A single outbound network request observed by the sandbox egress layer.

  Requests are emitted by `Condukt.Sandbox.NetworkPolicy`-capable sandboxes
  (today, `Condukt.Sandbox.Kubernetes` via the `condukt-egress` sidecar) and
  surfaced through telemetry on the BEAM side. See
  `Condukt.Sandbox.NetworkPolicy` for the event taxonomy.

  Method, path, request headers, request body sha256/preview, response
  status, response headers, response body sha256/preview, and byte counts
  are populated by the sidecar after MITM TLS termination. Fields the
  sidecar could not derive (e.g. for cleartext or pre-handshake events)
  remain `nil`.

  Bodies and headers may be partially redacted by the sidecar according to
  the `Condukt.Sandbox.NetworkPolicy` redaction patterns.
  """

  defstruct id: nil,
            session_id: nil,
            host: nil,
            port: 443,
            remote_addr: nil,
            method: nil,
            path: nil,
            scheme: "https",
            request_headers: nil,
            request_body_sha256: nil,
            request_body_preview: nil,
            request_body_truncated: false,
            response_status: nil,
            response_headers: nil,
            response_body_sha256: nil,
            response_body_preview: nil,
            response_body_truncated: false,
            bytes_in: 0,
            bytes_out: 0,
            started_at: nil,
            finished_at: nil,
            initiator: nil

  @doc """
  Decodes a request from the NDJSON wire format emitted by `condukt-egress`.

  Unknown keys are ignored so the protocol can evolve forward-compatibly.
  Required fields: `id`, `host`, `port`, `started_at`.
  """
  def from_json(%{"id" => id, "host" => host, "port" => port, "started_at" => started_at} = json) do
    with {:ok, started_at} <- parse_datetime(started_at),
         {:ok, finished_at} <- parse_optional_datetime(Map.get(json, "finished_at")) do
      {:ok,
       %__MODULE__{
         id: id,
         session_id: Map.get(json, "session_id"),
         host: host,
         port: port,
         remote_addr: Map.get(json, "remote_addr"),
         method: Map.get(json, "method"),
         path: Map.get(json, "path"),
         scheme: Map.get(json, "scheme", "https"),
         request_headers: Map.get(json, "request_headers"),
         request_body_sha256: Map.get(json, "request_body_sha256"),
         request_body_preview: Map.get(json, "request_body_preview"),
         request_body_truncated: Map.get(json, "request_body_truncated", false),
         response_status: Map.get(json, "response_status"),
         response_headers: Map.get(json, "response_headers"),
         response_body_sha256: Map.get(json, "response_body_sha256"),
         response_body_preview: Map.get(json, "response_body_preview"),
         response_body_truncated: Map.get(json, "response_body_truncated", false),
         bytes_in: Map.get(json, "bytes_in", 0),
         bytes_out: Map.get(json, "bytes_out", 0),
         started_at: started_at,
         finished_at: finished_at,
         initiator: Map.get(json, "initiator")
       }}
    end
  end

  def from_json(other), do: {:error, {:invalid_request, other}}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_datetime, reason}}
    end
  end

  defp parse_datetime(other), do: {:error, {:invalid_datetime, other}}

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(value), do: parse_datetime(value)
end
