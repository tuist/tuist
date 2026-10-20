defmodule AtlasWeb.GTMTransactionalController do
  @moduledoc """
  Loops-compatible transactional endpoint.

  Mirrors `POST https://app.loops.so/api/v1/transactional`, so a caller such as
  the Tuist marketing site only swaps the base URL and the API key. The request
  takes `email`, `transactionalId`, and `dataVariables`, and the response is
  Loops' `%{success: true}` shape.
  """

  use AtlasWeb, :controller

  alias Atlas.GTM
  alias AtlasWeb.GTMIngestAuth

  require Logger

  def create(conn, params) do
    with :ok <- GTMIngestAuth.authorize(conn),
         {:ok, result} <-
           GTM.send_email_transactional(
             params["transactionalId"],
             params["email"],
             params["dataVariables"] || %{}
           ) do
      conn
      |> put_status(:ok)
      |> json(%{success: true, id: result.delivery.id, duplicate: result.duplicate})
    else
      {:error, :not_configured} ->
        Logger.warning("Transactional send received but ATLAS_GTM_INGEST_TOKEN is not configured")
        conn |> put_status(:unauthorized) |> json(%{success: false, message: "not configured"})

      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{success: false, message: "invalid API key"})

      {:error, :email_missing} ->
        conn |> put_status(:bad_request) |> json(%{success: false, message: "email is required"})

      {:error, :unknown_transactional_id} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, message: "unknown transactionalId"})

      {:error, {:missing_variables, missing}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, message: "missing data variables: #{Enum.join(missing, ", ")}"})

      {:error, reason} ->
        Logger.error("Could not queue transactional email: #{inspect(reason)}")
        conn |> put_status(:internal_server_error) |> json(%{success: false, message: "not queued"})
    end
  end
end
