defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.Authentication
  alias Cache.Disk

  def load(conn, %{"id" => id, "account_handle" => account_handle, "project_handle" => project_handle}) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        IO.puts("CAS Controller: attempting to load #{id}")
        key = cas_key(account_handle, project_handle, id)

        if Disk.exists?(key) do
          IO.puts("CAS Controller: found #{id}")
          stream = Disk.stream(key)

          conn
          |> put_resp_content_type("application/octet-stream")
          |> send_chunked(200)
          |> stream_data(stream)
        else
          IO.puts("CAS Controller: not found #{id}")

          conn
          |> put_status(:not_found)
          |> json(%{message: "Artifact does not exist"})
        end

      {:error, status, message} ->
        IO.puts("CAS Controller: unauthorized #{id}")

        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end

  defp cas_key(account_handle, project_handle, id) do
    "#{account_handle}/#{project_handle}/cas/#{id}"
  end

  def save(conn, %{"id" => id, "account_handle" => account_handle, "project_handle" => project_handle}) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        IO.puts("CAS Controller: attempting to save #{id}")
        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 100_000_000)
        key = cas_key(account_handle, project_handle, id)

        if Disk.exists?(key) do
          IO.puts("CAS Controller: already exists #{id}")
          send_resp(conn, :no_content, "")
        else
          IO.puts("CAS Controller: saving #{id}")
          Disk.put(key, body)
          IO.puts("CAS Controller: saved #{id}")
          send_resp(conn, :no_content, "")
        end

      {:error, status, message} ->
        IO.puts("CAS Controller: unauthorized #{id}")

        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end
end
