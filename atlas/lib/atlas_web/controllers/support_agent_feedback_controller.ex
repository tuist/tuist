defmodule AtlasWeb.SupportAgentFeedbackController do
  @moduledoc """
  Receives feedback that AI agents report through the Tuist MCP server and turns
  each report into a support conversation.
  """

  use AtlasWeb, :controller

  alias Atlas.RateLimit
  alias Atlas.Support
  alias AtlasWeb.IngestAuth

  require Logger

  # Agents can loop; cap how many conversations one user's agents can open.
  @per_address {:timer.hours(1), 10}

  def create(conn, params) do
    with :ok <- IngestAuth.authorize(conn, Support.ingest_token()),
         :ok <- check_rate_limit(params["email"]),
         {:ok, %{thread: thread}} <- Support.receive_agent_feedback(params) do
      conn
      |> put_status(:created)
      |> json(%{id: thread.id})
    else
      {:error, :not_configured} ->
        Logger.warning("Agent feedback received but ATLAS_SUPPORT_INGEST_TOKEN is not configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

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
