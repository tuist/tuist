defmodule TuistWeb.Plugs.InternalGrafanaAuthPlug do
  @moduledoc """
  Authenticates the Grafana internal read-only DB query endpoint with a static
  bearer token (`Tuist.Environment.grafana_db_query_token/0`), sourced from the
  server secret store. Grafana Cloud is not a Kubernetes workload, so it can't
  present the projected ServiceAccount token the Atlas path uses; this token is
  a separate, independently-revocable credential. The endpoint is meant to be
  reached over the private PDC tunnel, not the public internet.
  """

  use TuistWeb, :controller

  require Logger

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    case Tuist.Environment.grafana_db_query_token() do
      token when token in [nil, ""] ->
        Logger.error("grafana: db query token not configured")

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "grafana db access not configured"})
        |> halt()

      expected ->
        with {:ok, provided} <- bearer_token(conn),
             true <- Plug.Crypto.secure_compare(provided, expected) do
          conn
        else
          {:error, :missing_bearer} ->
            conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"}) |> halt()

          false ->
            Logger.warning("grafana: db query token rejected")
            conn |> put_status(:unauthorized) |> json(%{error: "invalid token"}) |> halt()
        end
    end
  end

  defp bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end
end
