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
  # Caps reports from all users together, so many accounts cannot flood the
  # support queue and Slack channel.
  @overall {:timer.hours(1), 100}

  def create(conn, params) do
    with :ok <- authenticate(conn),
         :ok <- check_rate_limit(params["email"]),
         {:ok, %{thread: thread}} <- Support.receive_agent_feedback(params) do
      conn
      |> put_status(:created)
      |> json(%{id: thread.id})
    else
      {:error, :not_configured} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "not configured"})

      {:error, :unauthorized} ->
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

  defp authenticate(conn) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> nil
      end

    case WorkloadIdentity.verify(token, Support.ingest_workload_identity_policy()) do
      :ok ->
        :ok

      {:error, :not_configured} ->
        Logger.error("Agent feedback received but ATLAS_SUPPORT_INGEST_TOKEN_* is not configured")
        {:error, :not_configured}

      {:error, reason} ->
        Logger.warning("Agent feedback workload token rejected: #{reason}")
        {:error, :unauthorized}
    end
  end

  defp check_rate_limit(email) do
    address = if is_binary(email), do: email |> String.trim() |> String.downcase(), else: ""

    with :ok <- hit("support_agent_feedback:address:" <> address, @per_address) do
      hit("support_agent_feedback:overall", @overall)
    end
  end

  defp hit(key, {scale, limit}) do
    case RateLimit.hit(key, scale, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, {:rate_limited, ceil(retry_after_ms / 1000)}}
    end
  end
end
