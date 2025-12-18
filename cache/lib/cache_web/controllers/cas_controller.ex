defmodule CacheWeb.CASController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.BodyReader
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.S3
  alias Cache.S3Transfers
  alias CacheWeb.API.Schemas.Error

  require Logger

  plug OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true

  tags(["CAS"])

  operation(:download,
    summary: "Download a CAS artifact",
    operation_id: "downloadCASArtifact",
    parameters: [
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The artifact identifier"
      ],
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ]
    ],
    responses: %{
      ok: {"Artifact content", "application/octet-stream", nil},
      not_found: {"Artifact not found", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def download(conn, %{id: id, account_handle: account_handle, project_handle: project_handle}) do
    :telemetry.execute([:cache, :cas, :download, :hit], %{}, %{})
    key = Disk.cas_key(account_handle, project_handle, id)
    :ok = CacheArtifacts.track_artifact_access(key)

    case Disk.cas_stat(account_handle, project_handle, id) do
      {:ok, %File.Stat{size: size}} ->
        local_path = Disk.cas_local_accel_path(account_handle, project_handle, id)

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

        S3Transfers.enqueue_cas_download(account_handle, project_handle, key)

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

  operation(:save,
    summary: "Save a CAS artifact",
    operation_id: "saveCASArtifact",
    parameters: [
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The artifact identifier"
      ],
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ]
    ],
    request_body: {"The CAS artifact data", "application/octet-stream", nil, required: true},
    responses: %{
      no_content: {"Upload successful", nil, nil},
      request_entity_too_large: {"Request body exceeded allowed size", "application/json", Error},
      request_timeout: {"Request body read timed out", "application/json", Error},
      internal_server_error: {"Failed to persist artifact", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def save(conn, %{id: id, account_handle: account_handle, project_handle: project_handle}) do
    if Disk.cas_exists?(account_handle, project_handle, id) do
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
        send_error(conn_after, :request_entity_too_large, "Request body exceeded allowed size")

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
    case Disk.cas_put(account_handle, project_handle, id, data) do
      :ok ->
        :telemetry.execute([:cache, :cas, :upload, :success], %{size: size}, %{
          cas_id: id,
          account_handle: account_handle,
          project_handle: project_handle
        })

        key = Disk.cas_key(account_handle, project_handle, id)
        :ok = CacheArtifacts.track_artifact_access(key)
        S3Transfers.enqueue_cas_upload(account_handle, project_handle, key)
        send_resp(conn, :no_content, "")

      {:error, :exists} ->
        cleanup_tmp_file(data)
        :telemetry.execute([:cache, :cas, :upload, :exists], %{count: 1}, %{})
        send_resp(conn, :no_content, "")

      {:error, _reason} ->
        cleanup_tmp_file(data)
        :telemetry.execute([:cache, :cas, :upload, :error], %{count: 1}, %{reason: :persist_error})
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{message: message})
  end

  defp cleanup_tmp_file({:file, tmp_path}), do: File.rm(tmp_path)
  defp cleanup_tmp_file(_binary_data), do: :ok
end
