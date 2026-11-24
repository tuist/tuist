defmodule TuistWeb.RemoteExecutionActionsController do
  @moduledoc """
  Receives the execution gateway's records of the actions it ran, in
  batches, with the credential that authorized those actions. See
  `Tuist.RemoteExecution.Actions`.
  """
  use TuistWeb, :controller

  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Actions

  plug(:authorize)

  # The answer carries presigned uploads for the ends of streams the records
  # only keep the start of; the gateway copies them in the background.
  def create(conn, %{"actions" => records}) do
    project = conn.assigns.execution_project

    case Actions.ingest(project, records) do
      {:ok, accepted} ->
        conn |> put_status(:accepted) |> json(%{accepted: accepted, log_uploads: Actions.log_uploads(project, records)})

      {:error, :invalid_request} ->
        invalid(conn)
    end
  end

  def create(conn, _params), do: invalid(conn)

  defp invalid(conn), do: conn |> put_status(:bad_request) |> json(%{message: "invalid action records"})

  # Records arrive after their actions ran, so they need the project
  # credential but not remote execution still being enabled.
  defp authorize(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    with ["Bearer " <> token] when byte_size(token) in 1..16_384 <- get_req_header(conn, "authorization"),
         %{"account" => account, "project" => project} <- conn.path_params,
         {:ok, project} <- RemoteExecution.authorize(token, account, project, require_enabled: false) do
      assign(conn, :execution_project, project)
    else
      _ -> conn |> put_status(:forbidden) |> json(%{message: "execution not authorized"}) |> halt()
    end
  end
end
