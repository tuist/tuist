defmodule CacheWeb.GradleController do
  @moduledoc """
  Controller for Gradle HTTP Build Cache protocol.

  Implements the Gradle build cache contract:
  - GET /:cache_key - Download a cached artifact (returns 200 with body or 404)
  - PUT /:cache_key - Upload a cached artifact (returns 200 or 201)

  See: https://docs.gradle.org/current/userguide/build_cache.html#sec:build_cache_configure_remote
  """
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

  tags(["Gradle"])

  operation(:download,
    summary: "Download a Gradle build cache artifact",
    operation_id: "downloadGradleArtifact",
    parameters: [
      cache_key: [
        in: :path,
        type: :string,
        required: true,
        description: "The Gradle build cache key (hash)"
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

  def download(conn, %{
        cache_key: cache_key,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    :telemetry.execute([:cache, :gradle, :download, :hit], %{}, %{})
    key = Disk.gradle_key(account_handle, project_handle, cache_key)

    case Disk.gradle_stat(account_handle, project_handle, cache_key) do
      {:ok, %File.Stat{size: size}} ->
        :ok = CacheArtifacts.track_artifact_access(key)

        :telemetry.execute([:cache, :gradle, :download, :disk_hit], %{size: size}, %{
          cache_key: cache_key,
          account_handle: account_handle,
          project_handle: project_handle
        })

        # In dev mode (MIX_ENV=dev), serve file directly since there's no nginx
        # In production, use X-Accel-Redirect for efficient file serving via nginx
        if Application.get_env(:cache, :env) == :dev do
          file_path = Disk.artifact_path(key)
          send_download(conn, {:file, file_path}, content_type: "application/octet-stream")
        else
          local_path = Disk.gradle_local_accel_path(account_handle, project_handle, cache_key)

          conn
          |> put_resp_header("x-accel-redirect", local_path)
          |> send_resp(:ok, "")
        end

      {:error, _} ->
        :telemetry.execute([:cache, :gradle, :download, :disk_miss], %{}, %{})

        # In dev mode, just return 404 since there's no S3
        if Application.get_env(:cache, :env) == :dev do
          send_resp(conn, :not_found, "")
        else
          S3Transfers.enqueue_gradle_download(account_handle, project_handle, key)

          case S3.presign_download_url(key) do
            {:ok, url} ->
              conn
              |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
              |> send_resp(:ok, "")

            {:error, reason} ->
              Logger.warning("Failed to presign S3 url for Gradle: #{inspect(reason)}")

              :telemetry.execute([:cache, :gradle, :download, :error], %{}, %{
                reason: inspect(reason)
              })

              send_resp(conn, :not_found, "")
          end
        end
    end
  end

  operation(:save,
    summary: "Save a Gradle build cache artifact",
    operation_id: "saveGradleArtifact",
    parameters: [
      cache_key: [
        in: :path,
        type: :string,
        required: true,
        description: "The Gradle build cache key (hash)"
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
    request_body:
      {"The Gradle build cache artifact data", "application/octet-stream", nil, required: true},
    responses: %{
      ok: {"Upload successful (artifact existed)", nil, nil},
      created: {"Upload successful (new artifact)", nil, nil},
      request_entity_too_large: {"Request body exceeded allowed size", "application/json", Error},
      request_timeout: {"Request body read timed out", "application/json", Error},
      internal_server_error: {"Failed to persist artifact", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def save(conn, %{
        cache_key: cache_key,
        account_handle: account_handle,
        project_handle: project_handle
      }) do
    if Disk.gradle_exists?(account_handle, project_handle, cache_key) do
      handle_existing_artifact(conn)
    else
      save_new_artifact(conn, account_handle, project_handle, cache_key)
    end
  end

  defp handle_existing_artifact(conn) do
    :telemetry.execute([:cache, :gradle, :upload, :exists], %{count: 1}, %{})

    case BodyReader.drain(conn) do
      {:ok, conn_after} -> send_resp(conn_after, :ok, "")
      {:error, conn_after} -> send_resp(conn_after, :ok, "")
    end
  end

  defp save_new_artifact(conn, account_handle, project_handle, cache_key) do
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

        :telemetry.execute([:cache, :gradle, :upload, :attempt], %{size: size}, %{})
        persist_artifact(conn_after, account_handle, project_handle, cache_key, data, size)

      {:error, :too_large, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :too_large})
        send_error(conn_after, :request_entity_too_large, "Request body exceeded allowed size")

      {:error, :timeout, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :timeout})
        send_error(conn_after, :request_timeout, "Request body read timed out")

      {:error, :cancelled, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :cancelled], %{count: 1}, %{})
        send_resp(conn_after, :ok, "")

      {:error, _reason, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :read_error})
        send_error(conn_after, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp persist_artifact(conn, account_handle, project_handle, cache_key, data, size) do
    case Disk.gradle_put(account_handle, project_handle, cache_key, data) do
      :ok ->
        :telemetry.execute([:cache, :gradle, :upload, :success], %{size: size}, %{
          cache_key: cache_key,
          account_handle: account_handle,
          project_handle: project_handle
        })

        key = Disk.gradle_key(account_handle, project_handle, cache_key)
        :ok = CacheArtifacts.track_artifact_access(key)
        S3Transfers.enqueue_gradle_upload(account_handle, project_handle, key)
        send_resp(conn, :created, "")

      {:error, :exists} ->
        cleanup_tmp_file(data)
        :telemetry.execute([:cache, :gradle, :upload, :exists], %{count: 1}, %{})
        send_resp(conn, :ok, "")

      {:error, _reason} ->
        cleanup_tmp_file(data)
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :persist_error})
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
