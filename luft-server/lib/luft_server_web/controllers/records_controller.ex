defmodule LuftServerWeb.RecordsController do
  use LuftServerWeb, :controller

  alias LuftServer.Workspaces.Records

  def show(conn, _params), do: perform(conn, :open)
  def query(conn, _params), do: perform(conn, :query)
  def execute(conn, _params), do: perform(conn, :action)

  defp perform(conn, operation) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    result =
      Records.request(
        conn.assigns.session,
        conn.path_params["account_handle"],
        conn.path_params["id"],
        conn.path_params["message_id"],
        operation,
        if(operation == :open, do: %{}, else: conn.body_params)
      )

    case result do
      {:ok, value} -> json(conn, value)
      {:error, %{code: "REVISION_CONFLICT"}} -> failure(conn, 409, "REVISION_CONFLICT")
      {:error, %{code: "NOT_FOUND"}} -> failure(conn, 404, "NOT_FOUND")
      {:error, :not_found} -> failure(conn, 404, "NOT_FOUND")
      {:error, %{code: "FORBIDDEN"}} -> failure(conn, 403, "FORBIDDEN")
      {:error, :forbidden} -> failure(conn, 403, "FORBIDDEN")
      {:error, :unavailable} -> failure(conn, 503, "UNAVAILABLE")
      {:error, %{code: "VALIDATION_FAILED"}} -> failure(conn, 422, "VALIDATION_FAILED")
      {:error, _} -> failure(conn, 422, "INVALID_REQUEST")
    end
  end

  defp failure(conn, status, code),
    do: conn |> put_status(status) |> json(%{error: %{code: code, message: "Record unavailable"}})
end
