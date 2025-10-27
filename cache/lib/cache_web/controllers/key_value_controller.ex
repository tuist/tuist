defmodule CacheWeb.KeyValueController do
  use CacheWeb, :controller
  alias Cache.Authentication
  alias Cache.KeyValueStore

  def get_value(conn, %{"account_handle" => account_handle, "project_handle" => project_handle, "cas_id" => cas_id}) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        values = KeyValueStore.get_key_value(cas_id, account_handle, project_handle)

        case values do
          [] ->
            conn
            |> put_status(:not_found)
            |> json(%{message: "No entries found for CAS ID #{cas_id}."})

          _ ->
            conn
            |> put_status(:ok)
            |> json(%{entries: Enum.map(values, fn value -> %{value: value} end)})
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
        %{"cas_id" => cas_id, "values" => values} = conn.body_params
        values = Enum.map(entries, fn entry -> entry.value end)
        :ok = KeyValueStore.put_key_value(cas_id, account_handle, project_handle, values)

        send_resp(conn, :no_content, "")

      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end
end
