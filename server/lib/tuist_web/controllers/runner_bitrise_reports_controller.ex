defmodule TuistWeb.RunnerBitriseReportsController do
  @moduledoc """
  Receives the build a runner VM's Bitrise agent took, from the build's
  start hook.

  Authenticates with the Bitrise report token minted at dispatch, which
  names the claimed build and its account and authorizes nothing else.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Bitrise
  alias Tuist.Runners.Bitrise.ReportToken

  require Logger

  @doc """
  `POST /api/internal/runners/jobs/bitrise/started`

      { "build_slug": "...", "app_slug": "..." }

  Idempotent, so the hook may retry.
  """
  def started(conn, params) do
    with {:ok, claimed} <- authenticate(conn),
         build_slug when is_binary(build_slug) and build_slug != "" <- Map.get(params, "build_slug"),
         app_slug when is_binary(app_slug) and app_slug != "" <- Map.get(params, "app_slug") do
      case Bitrise.record_build_started(claimed, build_slug, app_slug) do
        :ok ->
          send_resp(conn, :no_content, "")

        {:error, :no_session} ->
          conn |> put_status(:gone) |> json(%{error: "runner session is closed"})

        {:error, :invalid_build} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "build is not on a connected pool"})

        {:error, reason} ->
          Logger.error("runners: bitrise build start report failed",
            workflow_job_id: claimed.workflow_job_id,
            reason: inspect(reason)
          )

          conn |> put_status(:internal_server_error) |> json(%{error: "build start report failed"})
      end
    else
      {:error, :missing_bearer} -> conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})
      {:error, :expired} -> conn |> put_status(:unauthorized) |> json(%{error: "report token expired"})
      {:error, :invalid} -> conn |> put_status(:unauthorized) |> json(%{error: "invalid report token"})
      _ -> conn |> put_status(:bad_request) |> json(%{error: "build_slug and app_slug are required"})
    end
  end

  defp authenticate(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> ReportToken.verify(token)
      _ -> {:error, :missing_bearer}
    end
  end
end
