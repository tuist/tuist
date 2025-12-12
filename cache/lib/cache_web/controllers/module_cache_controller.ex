defmodule CacheWeb.ModuleCacheController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.BodyReader
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.S3
  alias Cache.S3Transfers
  alias CacheWeb.API.Schemas.Error

  require Logger

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["ModuleCache"])

  operation(:download,
    summary: "Download a module cache artifact",
    operation_id: "downloadModuleCacheArtifact",
    parameters: [
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "Project ID (account_handle/project_handle)"
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
        description: "Cache category (builds, selective_tests)"
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

  def download(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, :hash),
         {:ok, name} <- fetch_param(params, :name) do
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
            S3Transfers.enqueue_module_download(account_handle, project_handle, category, hash, name)

            case S3.presign_download_url(key) do
              {:ok, url} ->
                conn
                |> put_resp_content_type("application/octet-stream")
                |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
                |> send_resp(:ok, "")

              {:error, reason} ->
                Logger.error("Failed to presign S3 URL for module artifact: #{inspect(reason)}")
                :telemetry.execute([:cache, :module, :download, :error], %{}, %{reason: inspect(reason)})
                send_not_found(conn)
            end
          else
            :telemetry.execute([:cache, :module, :download, :s3_miss], %{}, %{})
            send_not_found(conn)
          end
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  operation(:upload,
    summary: "Upload a module cache artifact",
    operation_id: "uploadModuleCacheArtifact",
    parameters: [
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "Project ID (account_handle/project_handle)"
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
        description: "Cache category (builds, selective_tests)"
      ]
    ],
    request_body: {"The artifact data", "application/octet-stream", nil, required: true},
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

  def upload(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, :hash),
         {:ok, name} <- fetch_param(params, :name) do
      category = Map.get(params, :cache_category, "builds")

      if Disk.module_exists?(account_handle, project_handle, category, hash, name) do
        handle_existing_artifact(conn)
      else
        save_new_artifact(conn, account_handle, project_handle, category, hash, name)
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  operation(:exists,
    summary: "Check if a module cache artifact exists",
    operation_id: "moduleCacheArtifactExists",
    parameters: [
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "Project ID (account_handle/project_handle)"
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
        description: "Cache category (builds, selective_tests)"
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

  def exists(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, :hash),
         {:ok, name} <- fetch_param(params, :name) do
      category = Map.get(params, :cache_category, "builds")
      key = Disk.module_key(account_handle, project_handle, category, hash, name)

      if Disk.module_exists?(account_handle, project_handle, category, hash, name) or S3.exists?(key) do
        send_resp(conn, :no_content, "")
      else
        conn
        |> put_status(:not_found)
        |> json(%{message: "Artifact not found"})
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  defp parse_project_id(%{project_id: project_id}) when is_binary(project_id) do
    case String.split(project_id, "/") do
      [account_handle, project_handle] -> {:ok, {account_handle, project_handle}}
      _ -> {:error, "Invalid project_id format. Expected 'account_handle/project_handle'"}
    end
  end

  defp parse_project_id(_), do: {:error, "Missing required parameter: project_id"}

  defp fetch_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "Missing required parameter: #{key}"}
      value -> {:ok, value}
    end
  end

  defp handle_existing_artifact(conn) do
    :telemetry.execute([:cache, :module, :upload, :exists], %{count: 1}, %{})

    case BodyReader.drain(conn) do
      {:ok, conn_after} -> send_resp(conn_after, :no_content, "")
      {:error, conn_after} -> send_resp(conn_after, :no_content, "")
    end
  end

  defp save_new_artifact(conn, account_handle, project_handle, category, hash, name) do
    case BodyReader.read(conn) do
      {:ok, data, conn_after} ->
        size = get_data_size(data)
        :telemetry.execute([:cache, :module, :upload, :attempt], %{size: size}, %{})
        persist_artifact(conn_after, account_handle, project_handle, category, hash, name, data, size)

      {:error, :too_large, conn_after} ->
        :telemetry.execute([:cache, :module, :upload, :error], %{count: 1}, %{reason: :too_large})
        send_error(conn_after, :request_entity_too_large, "Request body exceeded allowed size")

      {:error, :timeout, conn_after} ->
        :telemetry.execute([:cache, :module, :upload, :error], %{count: 1}, %{reason: :timeout})
        send_error(conn_after, :request_timeout, "Request body read timed out")

      {:error, :cancelled, conn_after} ->
        :telemetry.execute([:cache, :module, :upload, :cancelled], %{count: 1}, %{})
        send_resp(conn_after, :no_content, "")

      {:error, _reason, conn_after} ->
        :telemetry.execute([:cache, :module, :upload, :error], %{count: 1}, %{reason: :read_error})
        send_error(conn_after, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp get_data_size({:file, tmp_path}) do
    case File.stat(tmp_path) do
      {:ok, %File.Stat{size: sz}} -> sz
      _ -> 0
    end
  end

  defp get_data_size(bin) when is_binary(bin), do: byte_size(bin)

  defp persist_artifact(conn, account_handle, project_handle, category, hash, name, data, size) do
    case Disk.module_put(account_handle, project_handle, category, hash, name, data) do
      :ok ->
        key = Disk.module_key(account_handle, project_handle, category, hash, name)

        :telemetry.execute([:cache, :module, :upload, :success], %{size: size}, %{
          category: category,
          hash: hash,
          name: name,
          account_handle: account_handle,
          project_handle: project_handle
        })

        :ok = CacheArtifacts.track_artifact_access(key)
        S3Transfers.enqueue_module_upload(account_handle, project_handle, category, hash, name)
        send_resp(conn, :no_content, "")

      {:error, :exists} ->
        :telemetry.execute([:cache, :module, :upload, :exists], %{count: 1}, %{})
        send_resp(conn, :no_content, "")

      {:error, _reason} ->
        :telemetry.execute([:cache, :module, :upload, :error], %{count: 1}, %{reason: :persist_error})
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{message: message})
  end

  defp send_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{message: "Artifact not found"})
  end
end
