defmodule AtlasWeb.SignalEventController do
  use AtlasWeb, :controller

  alias Atlas.RateLimit
  alias Atlas.Signals.MCPEvents

  def create(conn, %{"id" => id}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with {:allow, _} <- RateLimit.hit("signal-event:#{:inet.ntoa(conn.remote_ip)}", 60_000, 60),
         {:ok, result} <- MCPEvents.receive_event(id, conn.req_headers, conn.private[:raw_body]) do
      case result do
        %{challenge: challenge} -> json(conn, %{challenge: challenge})
        %{id: id} -> conn |> put_status(:accepted) |> json(%{accepted: true, signal_id: id})
      end
    else
      {:deny, _} -> conn |> put_status(:too_many_requests) |> json(%{error: "rate_limited"})
      {:error, :payload_too_large} -> conn |> put_status(:payload_too_large) |> json(%{error: "payload_too_large"})
      {:error, :idempotency_conflict} -> conn |> put_status(:conflict) |> json(%{error: "idempotency_conflict"})
      {:error, :signals_disabled} -> conn |> put_status(:service_unavailable) |> json(%{error: "signals_disabled"})
      {:error, :source_disabled} -> conn |> put_status(:conflict) |> json(%{error: "source_disabled"})
      {:error, :unauthorized} -> conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
      _ -> conn |> put_status(:unprocessable_entity) |> json(%{error: "event_not_admitted"})
    end
  end
end
