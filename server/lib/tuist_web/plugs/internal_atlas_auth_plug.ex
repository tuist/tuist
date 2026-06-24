defmodule TuistWeb.Plugs.InternalAtlasAuthPlug do
  @moduledoc false

  use TuistWeb, :controller

  alias Tuist.AtlasWorkloadIdentity

  require Logger

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, principal} <- AtlasWorkloadIdentity.verify(token) do
      assign(conn, :atlas_principal, principal)
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"}) |> halt()

      {:error, reason} when reason in [:not_configured, :invalid_jwks] ->
        Logger.error("atlas: workload identity verifier unavailable", reason: inspect(reason))

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "workload identity unavailable"})
        |> halt()

      {:error, {:wrong_principal, %{namespace: namespace, name: name}}} ->
        Logger.warning("atlas: unauthorized principal",
          principal_namespace: namespace,
          principal_name: name
        )

        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized principal"}) |> halt()

      {:error, reason}
      when reason in [
             :invalid_token,
             :invalid_signature,
             :token_expired,
             :token_not_yet_valid,
             :missing_issued_at,
             :token_ttl_exceeded,
             :bad_issuer,
             :bad_audience,
             :not_service_account,
             :bad_kubernetes_claims
           ] ->
        Logger.warning("atlas: workload identity token rejected", reason: inspect(reason))
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"}) |> halt()
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
