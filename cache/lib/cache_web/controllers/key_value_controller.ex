defmodule CacheWeb.KeyValueController do
  use CacheWeb, :controller

  alias Cache.KeyValueStore

  def get_value(conn, %{"cas_id" => cas_id}) do
    :telemetry.execute([:cache, :kv, :get, :request], %{count: 1}, %{})
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]

    case KeyValueStore.get_key_value(cas_id, account_handle, project_handle) do
      {:ok, payload} ->
        :telemetry.execute([:cache, :kv, :get, :hit], %{bytes: byte_size(payload)}, %{})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(:ok, payload)

      {:error, :not_found} ->
        :telemetry.execute([:cache, :kv, :get, :miss], %{count: 1}, %{})

        conn
        |> put_status(:not_found)
        |> json(%{message: "No entries found for CAS ID #{cas_id}."})
    end
  end

  def put_value(conn, _params) do
    :telemetry.execute([:cache, :kv, :put, :request], %{count: 1}, %{})
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]
    %{"cas_id" => cas_id, "entries" => entries} = conn.body_params
    values = Enum.map(entries, fn entry -> entry["value"] end)

    case KeyValueStore.put_key_value(cas_id, account_handle, project_handle, values) do
      :ok ->
        :telemetry.execute([:cache, :kv, :put, :success], %{entries_count: length(values)}, %{})

      {:error, reason} ->
        :telemetry.execute([:cache, :kv, :put, :error], %{count: 1}, %{reason: inspect(reason)})
    end

    send_resp(conn, :no_content, "")
  end
end
