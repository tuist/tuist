defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.BodyReader
  alias Cache.Disk

  def authorize(conn, %{"account_handle" => account, "project_handle" => project})
      when is_binary(account) and account != "" and is_binary(project) and project != "" do
    send_resp(conn, :no_content, "")
  end

  def authorize(conn, _params), do: send_resp(conn, 400, "")

  defp cas_key(account_handle, project_handle, id) do
    "#{account_handle}/#{project_handle}/cas/#{id}"
  end

  def save(conn, %{"id" => id}) do
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]
    key = cas_key(account_handle, project_handle, id)

    if Disk.exists?(key) do
      handle_existing_artifact(conn)
    else
      save_new_artifact(conn, key)
    end
  end

  defp handle_existing_artifact(conn) do
    case BodyReader.drain(conn) do
      {:ok, conn_after} -> send_resp(conn_after, :no_content, "")
      {:error, conn_after} -> send_resp(conn_after, :no_content, "")
    end
  end

  defp save_new_artifact(conn, key) do
    case BodyReader.read(conn) do
      {:ok, data, conn_after} ->
        persist_artifact(conn_after, key, data)

      {:error, :too_large, conn_after} ->
        send_error(conn_after, :payload_too_large, "Request body exceeded allowed size")

      {:error, :timeout, conn_after} ->
        send_error(conn_after, :request_timeout, "Request body read timed out")

      {:error, _reason, conn_after} ->
        send_error(conn_after, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp persist_artifact(conn, key, data) do
    case Disk.put(key, data) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :exists} ->
        send_resp(conn, :no_content, "")

      {:error, _reason} ->
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{message: message})
  end
end
