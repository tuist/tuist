defmodule AtlasWeb.SupportAgentFeedbackController do
  @moduledoc """
  Receives feedback that AI agents report through a product's agent integration,
  such as an MCP server, and turns each report into a support conversation.
  """

  use AtlasWeb, :controller

  alias Atlas.RateLimit
  alias Atlas.Support
  alias Atlas.WorkloadIdentity

  require Logger

  # Agents can loop; cap how many conversations one user's agents can open.
  @per_address {:timer.hours(1), 10}

  def create(conn, params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, _principal} <- WorkloadIdentity.verify(token, Support.ingest_workload_identity_policy()),
         :ok <- check_rate_limit(params["email"]),
         {:ok, %{thread: thread}} <- Support.receive_agent_feedback(params) do
      conn
      |> put_status(:created)
      |> json(%{id: thread.id})
    else
      {:error, reason} when reason in [:not_configured, :invalid_jwks] ->
        Logger.error("Agent feedback received but the support ingest workload identity is not configured: #{reason}")

        conn |> put_status(:service_unavailable) |> json(%{error: "not configured"})

      {:error, {:wrong_principal, principal}} ->
        Logger.warning("Agent feedback rejected for unauthorized workload #{principal.namespace}:#{principal.name}")

        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, reason}
      when reason in [
             :missing_bearer,
             :invalid_token,
             :invalid_signature,
             :bad_issuer,
             :bad_audience,
             :token_expired,
             :token_not_yet_valid,
             :token_ttl_exceeded,
             :not_service_account,
             :bad_kubernetes_claims
           ] ->
        Logger.warning("Agent feedback workload token rejected: #{reason}")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, {:rate_limited, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{error: "rate limited"})

      {:error, reason} when is_atom(reason) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: Atom.to_string(reason)})
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [header] ->
        case String.split(header, " ", parts: 2) do
          [scheme, token] when token != "" ->
            if String.downcase(scheme) == "bearer", do: {:ok, token}, else: {:error, :missing_bearer}

          _ ->
            {:error, :missing_bearer}
        end

      _ ->
        {:error, :missing_bearer}
    end
  end

  defp check_rate_limit(email) when is_binary(email) do
    {scale, limit} = @per_address
    key = "support_agent_feedback:address:" <> (email |> String.trim() |> String.downcase())

    case RateLimit.hit(key, scale, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, {:rate_limited, ceil(retry_after_ms / 1000)}}
    end
  end

  defp check_rate_limit(_email), do: :ok
end
