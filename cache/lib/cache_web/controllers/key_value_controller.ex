defmodule CacheWeb.KeyValueController do
  use CacheWeb, :controller

  alias Cache.KeyValueStore

  def get_value(conn, %{"cas_id" => cas_id}) do
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]

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
  end

  def put_value(conn, _params) do
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]
    %{"cas_id" => cas_id, "entries" => entries} = conn.body_params
    values = Enum.map(entries, fn entry -> entry["value"] end)
    :ok = KeyValueStore.put_key_value(cas_id, account_handle, project_handle, values)

    send_resp(conn, :no_content, "")
  end
end
