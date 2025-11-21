defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.BodyReader
  alias Cache.CASArtifacts
  alias Cache.Disk
  alias Cache.S3
  alias Cache.S3DownloadWorker
  alias Cache.S3UploadWorker

  require Logger

  def download(conn, %{"id" => id, "account_handle" => account_handle, "project_handle" => project_handle}) do
    :telemetry.execute([:cache, :cas, :download, :hit], %{}, %{})
    key = Disk.cas_key(account_handle, project_handle, id)
    :ok = CASArtifacts.track_artifact_access(key)

    case Disk.stat(account_handle, project_handle, id) do
      {:ok, %File.Stat{size: size}} ->
        local_path = Disk.local_accel_path(account_handle, project_handle, id)

        :telemetry.execute([:cache, :cas, :download, :disk_hit], %{size: size}, %{
          cas_id: id,
          account_handle: account_handle,
          project_handle: project_handle
        })

        conn
        |> put_resp_header("x-accel-redirect", local_path)
        |> send_resp(:ok, "")

      {:error, _} ->
        :telemetry.execute([:cache, :cas, :download, :disk_miss], %{}, %{})

        Task.start(fn ->
          S3DownloadWorker.enqueue_download(account_handle, project_handle, id)
        end)

        case S3.presign_download_url(key) do
          {:ok, url} ->
            conn
            |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
            |> send_resp(:ok, "")

          {:error, reason} ->
            Appsignal.send_error(%RuntimeError{message: "Failed to presign S3 url"}, %{
              key: key,
              reason: reason
            })

            :telemetry.execute([:cache, :cas, :download, :error], %{}, %{reason: inspect(reason)})

            send_resp(conn, :not_found, "")
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
    :telemetry.execute([:cache, :cas, :upload, :exists], %{count: 1}, %{})

    case BodyReader.drain(conn) do
      {:ok, conn_after} -> send_resp(conn_after, :no_content, "")
      {:error, conn_after} -> send_resp(conn_after, :no_content, "")
    end
  end

  defp save_new_artifact(conn, account_handle, project_handle, id) do
    case BodyReader.read(conn) do
      {:ok, data, conn_after} ->
        size =
          case data do
            {:file, tmp_path} ->
              case File.stat(tmp_path) do
                {:ok, %File.Stat{size: sz}} -> sz
                _ -> 0
              end

            bin when is_binary(bin) ->
              byte_size(bin)
          end

        :telemetry.execute([:cache, :cas, :upload, :attempt], %{size: size}, %{})
        persist_artifact(conn_after, account_handle, project_handle, id, data, size)

      {:error, :too_large, conn_after} ->
        :telemetry.execute([:cache, :cas, :upload, :error], %{count: 1}, %{reason: :too_large})
        send_error(conn_after, :payload_too_large, "Request body exceeded allowed size")

      {:error, :timeout, conn_after} ->
        :telemetry.execute([:cache, :cas, :upload, :error], %{count: 1}, %{reason: :timeout})
        send_error(conn_after, :request_timeout, "Request body read timed out")

      {:error, :cancelled, conn_after} ->
        :telemetry.execute([:cache, :cas, :upload, :cancelled], %{count: 1}, %{})
        send_resp(conn_after, :no_content, "")

      {:error, _reason, conn_after} ->
        :telemetry.execute([:cache, :cas, :upload, :error], %{count: 1}, %{reason: :read_error})
        send_error(conn_after, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp persist_artifact(conn, account_handle, project_handle, id, data, size) do
    case Disk.put(account_handle, project_handle, id, data) do
      :ok ->
        :telemetry.execute([:cache, :cas, :upload, :success], %{size: size}, %{
          cas_id: id,
          account_handle: account_handle,
          project_handle: project_handle
        })

        :ok = CASArtifacts.track_artifact_access(Disk.cas_key(account_handle, project_handle, id))
        S3UploadWorker.enqueue_upload(account_handle, project_handle, id)
        send_resp(conn, :no_content, "")

      {:error, :exists} ->
        :telemetry.execute([:cache, :cas, :upload, :exists], %{count: 1}, %{})
        send_resp(conn, :no_content, "")

      {:error, _reason} ->
        :telemetry.execute([:cache, :cas, :upload, :error], %{count: 1}, %{reason: :persist_error})
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{message: message})
  end
end
