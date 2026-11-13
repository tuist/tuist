defmodule TuistOpsWeb.AtlasElevationController do
  @moduledoc """
  `POST /api/v1/atlas/elevations`: grants an orb thread elevation that
  its requester approved in Atlas.

  An agent calls Atlas' `request_cluster_elevation` MCP tool, Atlas
  holds the call until the person it acts for approves that exact call
  at `/approvals`, and only then calls this endpoint with the person's
  Atlas email. Atlas authenticates with its projected ServiceAccount
  token (`TuistOps.AtlasIdentity`); this endpoint trusts Atlas for the
  email and the approval, and still requires an engineering tailnet
  role for the email, as the Slack flow does. The elevation only takes
  effect when that email created the thread.

  Body: `email`, `env` (`canary` | `production`), `thread_id`,
  `intent`, `ttl_seconds`, `approval_id`.
  """
  use TuistOpsWeb, :controller

  alias TuistOps.AtlasIdentity
  alias TuistOps.JIT.Approvals

  plug :require_atlas_identity

  @env_groups %{
    "canary" => "group:tuist-canary-write",
    "production" => "group:tuist-production-write"
  }

  def create(conn, params) do
    attrs = %{
      requester_email: params["email"],
      target_group: Map.get(@env_groups, params["env"]),
      orb_thread_id: params["thread_id"],
      intent: params["intent"],
      ttl_seconds: params["ttl_seconds"],
      atlas_approval_id: params["approval_id"] && to_string(params["approval_id"])
    }

    case Approvals.grant_atlas_approved(attrs) do
      {:ok, _request, elevation} ->
        conn
        |> put_status(:created)
        |> json(%{
          elevation_id: elevation.id,
          env: params["env"],
          thread_id: elevation.orb_thread_id,
          expires_at: elevation.expires_at
        })

      {:error, :not_elevatable} ->
        error(conn, :unprocessable_entity, "env must be canary or production")

      {:error, :not_authorized} ->
        error(conn, :forbidden, "#{params["email"]} has no engineering tailnet role")

      {:error, :approval_already_used} ->
        error(conn, :conflict, "this Atlas approval already granted an elevation")

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          Enum.map_join(changeset.errors, "; ", fn {field, {msg, _}} -> "#{field} #{msg}" end)

        error(conn, :unprocessable_entity, message)
    end
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end

  defp require_atlas_identity(conn, _opts) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token | _] -> token
        _ -> nil
      end

    case AtlasIdentity.verify(token) do
      :ok -> conn
      {:error, _reason} -> conn |> error(:unauthorized, "not authenticated as Atlas") |> halt()
    end
  end
end
