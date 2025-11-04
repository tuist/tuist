defmodule CacheWeb.Plugs.AuthPlug do
  @moduledoc """
  Plug to authenticate requests for project access.

  This plug validates that a request has proper authorization to access a project
  by calling the server's /api/projects endpoint and caching the results.

  ## Usage

      plug CacheWeb.Plugs.AuthPlug

  The plug extracts account_handle and project_handle from the path parameters
  and halts the connection if authentication fails.
  """

  import Plug.Conn
  require Logger

  alias Cache.Authentication

  def init(opts), do: opts

  def call(conn, _opts) do
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]

    cond do
      is_nil(account_handle) or account_handle == "" ->
        error_response(conn, 400, "Missing account_handle")

      is_nil(project_handle) or project_handle == "" ->
        error_response(conn, 400, "Missing project_handle")

      true ->
        case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
          {:ok, _auth_header} ->
            conn

          {:error, status, message} ->
            error_response(conn, status, message)
        end
    end
  end

  defp error_response(conn, status, message) do
    if String.contains?(conn.request_path, "/auth/cas") do
      conn
      |> send_resp(status, "")
      |> halt()
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(%{message: message}))
      |> halt()
    end
  end
end
