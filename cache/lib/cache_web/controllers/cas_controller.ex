defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.Authentication
  alias Cache.BodyReader
  alias Cache.Disk
  alias Cache.S3UploadWorker

  def authorize(conn, %{"account_handle" => account, "project_handle" => project})
      when is_binary(account) and account != "" and is_binary(project) and project != "" do
    case Authentication.ensure_project_accessible(conn, account, project) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, status, _} -> send_resp(conn, status, "")
    end
  end

  def authorize(conn, _params), do: send_resp(conn, 400, "")

  def save(conn, %{"id" => id}) do
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]

    if Disk.exists?(account_handle, project_handle, id) do
      handle_existing_artifact(conn)
    else
      save_new_artifact(conn, account_handle, project_handle, id)
    end
  end

  defp handle_existing_artifact(conn) do
    case BodyReader.drain(conn) do
      {:ok, conn_after} -> send_resp(conn_after, :no_content, "")
      {:error, conn_after} -> send_resp(conn_after, :no_content, "")
    end
  end

  defp save_new_artifact(conn, account_handle, project_handle, id) do
    case BodyReader.read(conn) do
      {:ok, data, conn_after} ->
        persist_artifact(conn_after, account_handle, project_handle, id, data)

      {:error, :too_large, conn_after} ->
        send_error(conn_after, :payload_too_large, "Request body exceeded allowed size")

      {:error, :timeout, conn_after} ->
        send_error(conn_after, :request_timeout, "Request body read timed out")

      {:error, _reason, conn_after} ->
        send_error(conn_after, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp persist_artifact(conn, account_handle, project_handle, id, data) do
    case Disk.put(account_handle, project_handle, id, data) do
      :ok ->
        S3UploadWorker.enqueue_upload(account_handle, project_handle, id)
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
