defmodule CacheWeb.KeyValueController do
  use CacheWeb, :controller
  alias Cache.Authentication
  alias Cache.KeyValueStore

  def get_value(conn, %{"account_handle" => account_handle, "project_handle" => project_handle, "cas_id" => cas_id}) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        case KeyValueStore.get_key_value(cas_id, account_handle, project_handle) do
          {:ok, payload} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(:ok, payload)

          :not_found ->
            conn
            |> put_status(:not_found)
            |> json(%{message: "No entries found for CAS ID #{cas_id}."})
        end

      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end

  def put_value(conn, %{"account_handle" => account_handle, "project_handle" => project_handle}) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        %{"cas_id" => cas_id, "entries" => entries} = conn.body_params
        values = Enum.map(entries, fn entry -> entry["value"] end)
        :ok = KeyValueStore.put_key_value(cas_id, account_handle, project_handle, values)

        send_resp(conn, :no_content, "")

      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end
end
