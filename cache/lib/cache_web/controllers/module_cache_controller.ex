defmodule CacheWeb.ModuleCacheController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.BodyReader
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.MultipartUploads
  alias Cache.S3
  alias Cache.S3Transfers
  alias CacheWeb.API.Schemas.CompleteMultipartUploadRequest
  alias CacheWeb.API.Schemas.Error
  alias CacheWeb.API.Schemas.StartMultipartUploadResponse

  require Logger

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback CacheWeb.CacheFallbackController

  tags(["ModuleCache"])

  @max_part_size 10 * 1024 * 1024

  operation(:download,
    summary: "Download a module cache artifact",
    operation_id: "downloadModuleCacheArtifact",
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
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "Artifact hash"
      ],
      name: [
        in: :query,
        type: :string,
        required: true,
        description: "Artifact name"
      ],
      cache_category: [
        in: :query,
        type: :string,
        required: false,
        description: "Cache category (builds)"
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

  def download(
        conn,
        %{id: _id, account_handle: account_handle, project_handle: project_handle, hash: hash, name: name} = params
      ) do
    category = Map.get(params, :cache_category, "builds")
    key = Disk.module_key(account_handle, project_handle, category, hash, name)

    :telemetry.execute([:cache, :module, :download, :hit], %{}, %{})
    :ok = CacheArtifacts.track_artifact_access(key)

    case Disk.module_stat(account_handle, project_handle, category, hash, name) do
      {:ok, %File.Stat{size: size}} ->
        local_path = Disk.module_local_accel_path(account_handle, project_handle, category, hash, name)

        :telemetry.execute([:cache, :module, :download, :disk_hit], %{size: size}, %{
          category: category,
          hash: hash,
          name: name,
          account_handle: account_handle,
          project_handle: project_handle
        })

        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header("x-accel-redirect", local_path)
        |> send_resp(:ok, "")

      {:error, _} ->
        :telemetry.execute([:cache, :module, :download, :disk_miss], %{}, %{})

        if S3.exists?(key) do
          S3Transfers.enqueue_module_download(account_handle, project_handle, key)

          case S3.presign_download_url(key) do
            {:ok, url} ->
              conn
              |> put_resp_content_type("application/octet-stream")
              |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
              |> send_resp(:ok, "")

            {:error, reason} ->
              Logger.error("Failed to presign S3 URL for module artifact: #{inspect(reason)}")
              :telemetry.execute([:cache, :module, :download, :error], %{}, %{reason: inspect(reason)})
              {:error, :not_found}
          end
        else
          :telemetry.execute([:cache, :module, :download, :s3_miss], %{}, %{})
          {:error, :not_found}
        end
    end
  end

  operation(:exists,
    summary: "Check if a module cache artifact exists",
    operation_id: "moduleCacheArtifactExists",
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
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "Artifact hash"
      ],
      name: [
        in: :query,
        type: :string,
        required: true,
        description: "Artifact name"
      ],
      cache_category: [
        in: :query,
        type: :string,
        required: false,
        description: "Cache category (builds)"
      ]
    ],
    responses: %{
      no_content: {"Artifact exists", nil, nil},
      not_found: {"Artifact not found", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def exists(
        conn,
        %{id: _id, account_handle: account_handle, project_handle: project_handle, hash: hash, name: name} = params
      ) do
    category = Map.get(params, :cache_category, "builds")
    key = Disk.module_key(account_handle, project_handle, category, hash, name)

    if Disk.module_exists?(account_handle, project_handle, category, hash, name) or S3.exists?(key) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found}
    end
  end

  operation(:start_multipart,
    summary: "Start a multipart module cache upload",
    operation_id: "startModuleCacheMultipartUpload",
    parameters: [
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
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "Artifact hash"
      ],
      name: [
        in: :query,
        type: :string,
        required: true,
        description: "Artifact name"
      ],
      cache_category: [
        in: :query,
        type: :string,
        required: false,
        description: "Cache category (builds)"
      ]
    ],
    responses: %{
      ok: {"Upload started", "application/json", StartMultipartUploadResponse},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def start_multipart(
        conn,
        %{account_handle: account_handle, project_handle: project_handle, hash: hash, name: name} = params
      ) do
    category = Map.get(params, :cache_category, "builds")

    if Disk.module_exists?(account_handle, project_handle, category, hash, name) do
      json(conn, %{upload_id: nil})
    else
      {:ok, upload_id} = MultipartUploads.start_upload(account_handle, project_handle, category, hash, name)
      :telemetry.execute([:cache, :module, :multipart, :start], %{}, %{})
      json(conn, %{upload_id: upload_id})
    end
  end

  operation(:upload_part,
    summary: "Upload a part of a multipart module cache upload",
    operation_id: "uploadModuleCachePart",
    parameters: [
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
      ],
      upload_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The upload ID from start_multipart"
      ],
      part_number: [
        in: :query,
        type: :integer,
        required: true,
        description: "Part number (1-indexed)"
      ]
    ],
    request_body: {"The part data", "application/octet-stream", nil, required: true},
    responses: %{
      no_content: {"Part uploaded successfully", nil, nil},
      not_found: {"Upload not found", "application/json", Error},
      request_entity_too_large: {"Part exceeds 10MB limit", "application/json", Error},
      unprocessable_entity: {"Total upload size exceeds 500MB limit", "application/json", Error},
      request_timeout: {"Request body read timed out", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def upload_part(conn, %{upload_id: upload_id, part_number: part_number}) do
    case read_part_body(conn) do
      {:ok, tmp_path, size, conn_after} ->
        case MultipartUploads.add_part(upload_id, part_number, tmp_path, size) do
          :ok ->
            :telemetry.execute([:cache, :module, :multipart, :part], %{size: size, part_number: part_number}, %{})
            send_resp(conn_after, :no_content, "")

          {:error, :upload_not_found} ->
            File.rm(tmp_path)
            {:error, :not_found}

          {:error, :part_too_large} ->
            File.rm(tmp_path)
            {:error, :part_too_large}

          {:error, :total_size_exceeded} ->
            File.rm(tmp_path)
            {:error, :total_size_exceeded}
        end

      {:error, :too_large, _conn_after} ->
        {:error, :part_too_large}

      {:error, :timeout, _conn_after} ->
        {:error, :timeout}

      {:error, _reason, _conn_after} ->
        {:error, :persist_error}
    end
  end

  operation(:complete_multipart,
    summary: "Complete a multipart module cache upload",
    operation_id: "completeModuleCacheMultipartUpload",
    parameters: [
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
      ],
      upload_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The upload ID from start_multipart"
      ]
    ],
    request_body: {"Completion request", "application/json", CompleteMultipartUploadRequest, required: true},
    responses: %{
      no_content: {"Upload completed successfully", nil, nil},
      not_found: {"Upload not found", "application/json", Error},
      bad_request: {"Parts mismatch or missing parts", "application/json", Error},
      internal_server_error: {"Failed to assemble artifact", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def complete_multipart(conn, %{upload_id: upload_id}) do
    with {:ok, upload} <- MultipartUploads.complete_upload(upload_id),
         parts_from_client = Map.get(conn.body_params, :parts) || Map.get(conn.body_params, "parts"),
         :ok <- verify_parts(upload.parts, parts_from_client),
         part_paths = get_ordered_part_paths(upload.parts, parts_from_client),
         :ok <-
           Disk.module_put_from_parts(
             upload.account_handle,
             upload.project_handle,
             upload.category,
             upload.hash,
             upload.name,
             part_paths
           ) do
      Enum.each(part_paths, &File.rm/1)

      key = Disk.module_key(upload.account_handle, upload.project_handle, upload.category, upload.hash, upload.name)
      :ok = CacheArtifacts.track_artifact_access(key)
      S3Transfers.enqueue_module_upload(upload.account_handle, upload.project_handle, key)

      :telemetry.execute(
        [:cache, :module, :multipart, :complete],
        %{
          size: upload.total_bytes,
          parts_count: map_size(upload.parts)
        },
        %{}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, :parts_mismatch} -> {:error, :parts_mismatch}
      {:error, :exists} -> send_resp(conn, :no_content, "")
      {:error, _reason} -> {:error, :persist_error}
    end
  end

  defp read_part_body(conn) do
    opts = [max_bytes: @max_part_size, read_length: 262_144, read_timeout: 60_000]

    case BodyReader.read(conn, opts) do
      {:ok, {:file, tmp_path}, conn_after} ->
        case File.stat(tmp_path) do
          {:ok, %File.Stat{size: size}} -> {:ok, tmp_path, size, conn_after}
          _ -> {:error, :read_error, conn_after}
        end

      {:ok, data, conn_after} when is_binary(data) ->
        tmp_path = tmp_path()

        case File.write(tmp_path, data) do
          :ok -> {:ok, tmp_path, byte_size(data), conn_after}
          {:error, _} -> {:error, :read_error, conn_after}
        end

      {:error, reason, conn_after} ->
        {:error, reason, conn_after}
    end
  end

  defp tmp_path do
    base = System.tmp_dir!()
    unique = :erlang.unique_integer([:positive, :monotonic])
    Path.join(base, "cache-part-#{unique}")
  end

  defp verify_parts(server_parts, client_parts) do
    server_part_numbers = server_parts |> Map.keys() |> Enum.sort()
    client_part_numbers = Enum.sort(client_parts)

    if server_part_numbers == client_part_numbers do
      :ok
    else
      {:error, :parts_mismatch}
    end
  end

  defp get_ordered_part_paths(server_parts, client_parts) do
    Enum.map(client_parts, fn part_num ->
      server_parts[part_num].path
    end)
  end
end
