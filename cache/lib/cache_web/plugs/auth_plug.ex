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

  alias Cache.Authentication

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    {account_handle, project_handle} = extract_handles(conn.query_params)

    with {:ok, account} when account != "" <- {:ok, account_handle},
         {:ok, project} when project != "" <- {:ok, project_handle},
         {:ok, _auth_header} <- Authentication.ensure_project_accessible(conn, account, project) do
      conn
    else
      {:ok, _} -> error_response(conn, 400, "Missing account_handle")
      {:error, 400, _} -> error_response(conn, 400, "Missing project_handle")
      {:error, status, message} -> error_response(conn, status, message)
    end
  end

  defp extract_handles(%{"account_handle" => account, "project_handle" => project}) do
    {account, project}
  end

  defp extract_handles(%{"account_handle" => account}), do: {account, nil}
  defp extract_handles(%{"project_handle" => project}), do: {nil, project}
  defp extract_handles(_), do: {nil, nil}

  defp error_response(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{message: message}))
    |> halt()
  end
end
