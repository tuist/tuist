defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.BodyReader
  alias Cache.Disk
  alias Cache.S3
  alias Cache.S3UploadWorker

  require Logger

  def download(conn, %{"id" => id, "account_handle" => account_handle, "project_handle" => project_handle}) do
    key = Disk.cas_key(account_handle, project_handle, id)

    if Disk.exists?(account_handle, project_handle, id) do
      local_path = Disk.local_accel_path(account_handle, project_handle, id)

      conn
      |> put_resp_header("x-accel-redirect", local_path)
      |> send_resp(:ok, "")
    else
      case S3.presign_download_url(key) do
        {:ok, url} ->
          conn
          |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
          |> send_resp(:ok, "")

        {:error, reason} ->
          Logger.error("Failed to presign S3 URL for key #{key} with reason: #{inspect(reason)}")
          conn
          |> send_resp(:not_found, "")
      end
    end
  end

  def save(conn, %{"id" => id, "account_handle" => account_handle, "project_handle" => project_handle}) do
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
