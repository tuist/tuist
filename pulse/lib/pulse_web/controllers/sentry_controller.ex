defmodule PulseWeb.SentryController do
  use PulseWeb, :controller

  alias Plug.Parsers.RequestTooLargeError
  alias Pulse.Auth.Quota
  alias Pulse.Errors
  alias Pulse.Sentry
  alias Pulse.Sentry.Envelope
  alias PulseWeb.CompressedBodyReader

  # Relay's minimal 1×1 GIF response for pixel store ingestion.
  @pixel Base.decode64!("R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=")

  def envelope(conn, %{"project_id" => id}) do
    ingest_envelope(conn, id)
  end

  defp ingest_envelope(conn, project_id) do
    with {:ok, headers, event, discarded} <- Envelope.decode(conn.private.sentry_body),
         {:ok, id, project} <- Sentry.authorize(conn, project_id, headers) do
      ingest(conn, id, project, headers, event, discarded)
    else
      error -> failure(conn, error)
    end
  end

  def store(conn, _params) do
    case Sentry.authorize(conn, conn.path_params["project_id"], %{}) do
      {:ok, id, project} ->
        if conn.method == "POST" and get_req_header(conn, "content-type") == ["application/x-sentry-envelope"] do
          ingest_envelope(conn, conn.path_params["project_id"])
        else
          store_event(conn, id, project)
        end

      error ->
        failure(conn, error)
    end
  rescue
    RequestTooLargeError -> failure(conn, {:error, :event_too_large})
  end

  defp store_event(conn, id, project) do
    with {:ok, body} <- store_body(conn.private.sentry_body),
         true <- byte_size(body) <= 1_048_576,
         {:ok, event} when is_map(event) <- Pulse.JSON.decode(body) do
      ingest(conn, id, project, %{}, event, %{})
    else
      false -> failure(conn, {:error, :event_too_large})
      _ -> failure(conn, {:error, :invalid_event})
    end
  end

  defp store_body(body) when is_binary(body) do
    if String.starts_with?(String.trim_leading(body), "{") do
      {:ok, body}
    else
      case Base.decode64(body) do
        {:ok, <<"{", _::binary>> = decoded} -> {:ok, decoded}
        {:ok, decoded} -> CompressedBodyReader.uncompress(decoded, 1_048_576)
        error -> error
      end
    end
  end

  defp store_body(_), do: {:error, :invalid_event}

  defp ingest(conn, _id, _project, _headers, nil, discarded), do: success(conn, nil, discarded)

  defp ingest(conn, id, project, headers, event, discarded) do
    body = conn.private[:sentry_body]

    with :ok <- Pulse.Tenants.check(project["tenant"]),
         :ok <- Quota.charge(project["tenant"], if(is_binary(body), do: byte_size(body), else: 0)),
         {:ok, record} <- Errors.record(event, headers, id, project),
         :ok <- Pulse.Metrics.append(:logs, project["tenant"], [record], 0, []) do
      success(conn, record.resource["error_event_id"], discarded)
    else
      error -> failure(conn, error)
    end
  end

  defp success(%{method: "GET"} = conn, _id, _discarded) do
    conn |> put_resp_content_type("image/gif", nil) |> send_resp(200, @pixel)
  end

  defp success(conn, id, discarded) do
    count = Enum.sum(Map.values(discarded))
    conn = if count > 0, do: put_resp_header(conn, "x-pulse-discarded-items", to_string(count)), else: conn
    json(conn, %{id: id, discarded_items: discarded})
  end

  defp failure(conn, {:error, :invalid_sentry_key}), do: conn |> put_status(403) |> json(%{error: "invalid_sentry_key"})
  defp failure(conn, {:error, :forbidden}), do: conn |> put_status(403) |> json(%{error: "forbidden"})

  # Sentry SDKs back off on 429 using Retry-After.
  defp failure(conn, {:error, :rate_limited}),
    do: conn |> put_resp_header("retry-after", "10") |> put_status(429) |> json(%{error: "rate_limited"})

  defp failure(conn, {:error, reason})
       when reason in [:event_too_large, :too_many_items, :attributes_too_large, :too_many_records],
       do: conn |> put_status(413) |> json(%{error: to_string(reason)})

  defp failure(conn, {:error, reason})
       when reason in [
              :invalid_envelope,
              :multiple_events,
              :invalid_event,
              :invalid_event_id,
              :invalid_timestamp,
              :invalid_fingerprint,
              :retention_expired,
              :timestamp_too_new
            ], do: conn |> put_status(400) |> json(%{error: to_string(reason)})

  # Storage details can contain URLs/credentials. Do not expose them to SDKs.
  defp failure(conn, _error),
    do: conn |> put_resp_header("retry-after", "5") |> put_status(503) |> json(%{error: "storage_unavailable"})
end
