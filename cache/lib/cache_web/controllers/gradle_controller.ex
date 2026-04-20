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
  alias Cache.Gradle
  alias Cache.S3
  alias Cache.S3Transfers
  alias CacheWeb.API.Schemas.Error
  alias CacheWeb.API.Schemas.SafePathComponent

  require Logger

  @max_upload_bytes 100 * 1024 * 1024

  plug OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true

  tags(["Gradle"])

  operation(:download,
    summary: "Download a Gradle build cache artifact",
    operation_id: "downloadGradleArtifact",
    parameters: [
      cache_key: [
        in: :path,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The Gradle build cache key (hash)"
      ],
      account_handle: [
        in: :query,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The handle of the project"
      ]
    ],
    responses: %{
      ok: {"Artifact content", "application/octet-stream", nil},
      not_found: {"Artifact not found", "application/json", Error},
      unprocessable_entity: {"Invalid request parameters", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def download(conn, %{cache_key: cache_key, account_handle: account_handle, project_handle: project_handle}) do
    :telemetry.execute([:cache, :gradle, :download, :hit], %{}, %{})
    key = Gradle.Disk.key(account_handle, project_handle, cache_key)

    case Gradle.Disk.stat(account_handle, project_handle, cache_key) do
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
          local_path = Gradle.Disk.local_accel_path(account_handle, project_handle, cache_key)

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
        schema: SafePathComponent.schema(),
        required: true,
        description: "The Gradle build cache key (hash)"
      ],
      account_handle: [
        in: :query,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The handle of the project"
      ],
      "content-length": [
        in: :header,
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 0},
        required: true,
        description:
          "Declared body length in bytes. Required: `Cache.BodyReader` compares actual bytes " <>
            "received against this value to reject truncated uploads, so chunked transfer " <>
            "encoding (no Content-Length) is not accepted on this endpoint."
      ]
    ],
    request_body: {"The Gradle build cache artifact data", "application/octet-stream", nil, required: true},
    responses: %{
      ok: {"Upload successful (artifact existed)", nil, nil},
      created: {"Upload successful (new artifact)", nil, nil},
      bad_request:
        {"Request body was truncated before reaching the declared Content-Length", "application/json", Error},
      request_entity_too_large: {"Request body exceeded allowed size", "application/json", Error},
      request_timeout: {"Request body read timed out", "application/json", Error},
      internal_server_error: {"Failed to persist artifact", "application/json", Error},
      unprocessable_entity:
        {"Invalid or missing request parameters (e.g., missing Content-Length header)", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  # Gradle's client library uploads build cache entries as opaque gzipped blobs.
  # A client disconnect mid-upload can surface as an `{:ok, partial, conn}`
  # result from the HTTP adapter rather than an error, so we rely on
  # `Cache.BodyReader`'s Content-Length enforcement to distinguish complete
  # uploads from truncated ones. Without that enforcement, a partial gzip
  # stream can be persisted here and every subsequent download serves those
  # bytes with a 200 — the client then fails deep inside its snapshot parser
  # with a null-message exception that is very hard to trace back to the
  # upload path.
  #
  # The Content-Length header is declared `required: true` in the operation
  # spec above so `OpenApiSpex.Plug.CastAndValidate` rejects chunked-transfer
  # requests (no Content-Length) with a 422 before this function runs. That
  # keeps the enforcement in a single place — the spec — and guarantees the
  # validation pattern matches the generated OpenAPI documentation.
  def save(conn, %{cache_key: cache_key, account_handle: account_handle, project_handle: project_handle}) do
    if Gradle.Disk.exists?(account_handle, project_handle, cache_key) do
      handle_existing_artifact(conn)
    else
      save_new_artifact(conn, account_handle, project_handle, cache_key)
    end
  end

  defp handle_existing_artifact(conn) do
    :telemetry.execute([:cache, :gradle, :upload, :exists], %{count: 1}, %{})

    case BodyReader.drain(conn, max_bytes: @max_upload_bytes) do
      {:ok, conn_after} -> send_resp(conn_after, :ok, "")
      {:error, conn_after} -> send_resp(conn_after, :ok, "")
    end
  end

  defp save_new_artifact(conn, account_handle, project_handle, cache_key) do
    with {:ok, target_dir} <- Gradle.Disk.ensure_artifact_directory(account_handle, project_handle, cache_key),
         {:ok, data, conn_after} <- BodyReader.read(conn, max_bytes: @max_upload_bytes, tmp_dir: target_dir) do
      size = data_size(data)
      :telemetry.execute([:cache, :gradle, :upload, :attempt], %{size: size}, %{})
      persist_artifact(conn_after, account_handle, project_handle, cache_key, data, size)
    else
      {:error, :too_large, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :too_large})
        send_error(conn_after, :request_entity_too_large, "Request body exceeded allowed size")

      {:error, :timeout, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :timeout})
        send_error(conn_after, :request_timeout, "Request body read timed out")

      {:error, :cancelled, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :cancelled], %{count: 1}, %{})
        send_resp(conn_after, :ok, "")

      {:error, :truncated, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :truncated})

        send_error(
          conn_after,
          :bad_request,
          "Request body was truncated before reaching the declared Content-Length"
        )

      {:error, _reason, conn_after} ->
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :read_error})
        send_error(conn_after, :internal_server_error, "Failed to persist artifact")

      {:error, reason} ->
        Logger.error("Failed to ensure Gradle artifact directory: #{inspect(reason)}")
        :telemetry.execute([:cache, :gradle, :upload, :error], %{count: 1}, %{reason: :persist_error})
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp persist_artifact(conn, account_handle, project_handle, cache_key, data, size) do
    case Gradle.Disk.put(account_handle, project_handle, cache_key, data) do
      :ok ->
        :telemetry.execute([:cache, :gradle, :upload, :success], %{size: size}, %{
          cache_key: cache_key,
          account_handle: account_handle,
          project_handle: project_handle
        })

        key = Gradle.Disk.key(account_handle, project_handle, cache_key)
        :ok = CacheArtifacts.track_artifact_access(key)
        S3Transfers.enqueue_upload_if_missing(account_handle, project_handle, :gradle, key)
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

  defp data_size({:file, tmp_path}) do
    case File.stat(tmp_path) do
      {:ok, %File.Stat{size: sz}} -> sz
      _ -> 0
    end
  end

  defp data_size(bin) when is_binary(bin), do: byte_size(bin)

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{message: message})
  end

  defp cleanup_tmp_file({:file, tmp_path}), do: File.rm(tmp_path)
  defp cleanup_tmp_file(_binary_data), do: :ok
end
