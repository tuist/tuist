defmodule TuistWeb.API.CASController do
  use TuistWeb, :controller

  alias Tuist.Storage

  @doc """
  GET /api/cas/:hash - Download an object from CAS
  Streams the object from S3 storage
  """
  def get_object(conn, %{"hash" => hash}) do
    # TODO: Add project/account resolution later when we add authentication
    # For now, we'll need to determine how to map hash to object_key
    # This is a placeholder that will need project context
    project_slug = get_project_from_hash(hash)
    object_key = "#{String.downcase(project_slug)}/cas/#{hash}"

    # For now, use a default account until we add authentication
    account = get_default_account()

    case Storage.object_exists?(object_key, account) do
      true ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> send_chunked(200)
        |> stream_from_storage(object_key, account)

      false ->
        conn
        |> put_status(404)
        |> json(%{error: "Object not found"})
    end
  end

  @doc """
  HEAD /api/cas/:hash - Check if an object exists in CAS
  """
  def head_object(conn, %{"hash" => hash}) do
    project_slug = get_project_from_hash(hash)
    object_key = "#{String.downcase(project_slug)}/cas/#{hash}"
    account = get_default_account()

    case Storage.object_exists?(object_key, account) do
      true ->
        send_resp(conn, 200, "")

      false ->
        send_resp(conn, 404, "")
    end
  end

  @doc """
  PUT /api/cas/:hash - Upload an object to CAS
  Currently accepts the data in the request body
  """
  def put_object(conn, %{"hash" => hash}) do
    {:ok, body, conn} = read_body(conn)

    project_slug = get_project_from_hash(hash)
    object_key = "#{String.downcase(project_slug)}/cas/#{hash}"
    account = get_default_account()

    Storage.put_object(object_key, body, account)

    send_resp(conn, 201, "")
  end

  @doc """
  DELETE /api/cas/:hash - Delete an object from CAS
  Note: Delete is not implemented yet as it's not commonly used in CAS
  """
  def delete_object(conn, %{"hash" => _hash}) do
    # TODO: Implement delete if needed
    # For now, return 204 (success) as delete is idempotent
    send_resp(conn, 204, "")
  end

  @doc """
  GET /api/cas/ac/:hash - Get action cache entry
  """
  def get_action_cache(conn, %{"hash" => _hash}) do
    # Action cache implementation - maps action hash to CAS object hash
    # For now, this is a placeholder
    conn
    |> put_status(404)
    |> json(%{error: "Action cache not implemented yet"})
  end

  @doc """
  PUT /api/cas/ac/:hash - Store action cache entry
  """
  def put_action_cache(conn, %{"hash" => _hash}) do
    {:ok, _body, conn} = read_body(conn)

    # Action cache implementation - maps action hash to CAS object hash
    # For now, this is a placeholder
    send_resp(conn, 201, "")
  end

  # Private functions

  defp stream_from_storage(conn, object_key, account) do
    stream = Storage.stream_object(object_key, account)

    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} ->
          {:cont, conn}

        {:error, :closed} ->
          {:halt, conn}
      end
    end)
  end

  defp get_project_from_hash(_hash) do
    # TODO: This needs to be properly implemented
    # Options:
    # 1. Include project in query params
    # 2. Use a hash -> project mapping table
    # 3. Store project info in the hash itself
    # For now, return a placeholder
    "default/project"
  end

  defp get_default_account do
    # TODO: This needs to be properly implemented when we add authentication
    # For now, return nil which will use the default S3 configuration
    nil
  end
end
