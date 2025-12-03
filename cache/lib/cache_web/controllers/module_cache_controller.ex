defmodule CacheWeb.ModuleCacheController do
  use CacheWeb, :controller

  alias Cache.Disk
  alias Cache.S3

  require Logger

  # GET /api/cache
  # Query params: project_id, hash, name, cache_category
  def download(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, "hash"),
         {:ok, name} <- fetch_param(params, "name") do
      category = Map.get(params, "cache_category", "builds")

      :telemetry.execute([:cache, :module, :download, :hit], %{}, %{})
      key = Disk.module_key(account_handle, project_handle, category, hash, name)

      expires_in = 3600
      url = S3.generate_download_url(key, expires_in: expires_in)
      expires_at = System.system_time(:second) + expires_in

      json(conn, %{status: "success", data: %{url: url, expires_at: expires_at}})
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  # GET /api/cache/exists
  # Query params: project_id, hash, name, cache_category
  def exists(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, "hash"),
         {:ok, name} <- fetch_param(params, "name") do
      category = Map.get(params, "cache_category", "builds")

      key = Disk.module_key(account_handle, project_handle, category, hash, name)

      if Disk.module_exists?(account_handle, project_handle, category, hash, name) or S3.exists?(key) do
        json(conn, %{status: "success", data: %{}})
      else
        conn
        |> put_status(:not_found)
        |> json(%{errors: [%{message: "The artifact was not found", code: "not_found"}]})
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  # POST /api/cache/multipart/start
  # Query params: project_id, hash, name, cache_category
  def multipart_start(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, "hash"),
         {:ok, name} <- fetch_param(params, "name") do
      category = Map.get(params, "cache_category", "builds")

      key = Disk.module_key(account_handle, project_handle, category, hash, name)
      upload_id = S3.multipart_start(key)

      json(conn, %{status: "success", data: %{upload_id: upload_id}})
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  # POST /api/cache/multipart/generate-url
  # Query params: project_id, hash, name, cache_category, upload_id, part_number, content_length (optional)
  def multipart_generate_url(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, "hash"),
         {:ok, name} <- fetch_param(params, "name"),
         {:ok, upload_id} <- fetch_param(params, "upload_id"),
         {:ok, part_number} <- fetch_integer_param(params, "part_number") do
      category = Map.get(params, "cache_category", "builds")

      key = Disk.module_key(account_handle, project_handle, category, hash, name)
      url = S3.multipart_generate_url(key, upload_id, part_number)

      json(conn, %{status: "success", data: %{url: url}})
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  # POST /api/cache/multipart/complete
  # Query params: project_id, hash, name, cache_category, upload_id
  # Body: %{parts: [%{part_number: integer, etag: string}]}
  def multipart_complete(conn, params) do
    with {:ok, {account_handle, project_handle}} <- parse_project_id(params),
         {:ok, hash} <- fetch_param(params, "hash"),
         {:ok, name} <- fetch_param(params, "name"),
         {:ok, upload_id} <- fetch_param(params, "upload_id"),
         {:ok, parts} <- fetch_parts(params) do
      category = Map.get(params, "cache_category", "builds")

      key = Disk.module_key(account_handle, project_handle, category, hash, name)

      parts_tuples =
        Enum.map(parts, fn part ->
          {part["part_number"], part["etag"]}
        end)

      :ok = S3.multipart_complete(key, upload_id, parts_tuples)

      json(conn, %{status: "success", data: %{}})
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: message})
    end
  end

  # Helper functions

  defp parse_project_id(%{"project_id" => project_id}) when is_binary(project_id) do
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

  defp fetch_integer_param(params, key) do
    case Map.get(params, key) do
      nil ->
        {:error, "Missing required parameter: #{key}"}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> {:ok, int}
          _ -> {:error, "Invalid integer for parameter: #{key}"}
        end
    end
  end

  defp fetch_parts(%{"parts" => parts}) when is_list(parts), do: {:ok, parts}
  defp fetch_parts(_), do: {:error, "Missing required parameter: parts"}
end
