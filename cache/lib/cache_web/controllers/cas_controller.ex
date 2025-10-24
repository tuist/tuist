defmodule CacheWeb.CasController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.Storage
  alias CacheWeb.Schemas.Error

  # Only validate for get_value, not for save which handles binary data
  plug OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    only: [:get_value]

  tags ["CAS"]

  operation :get_value,
    summary: "Get CAS object",
    operation_id: "getCasObject",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The CAS object identifier"
      ]
    ],
    responses: %{
      200 => {"Object retrieved successfully", "application/octet-stream", nil},
      404 => {"Object not found", "application/json", Error},
      500 => {"Server error", "application/json", Error}
    }

  def get_value(conn, _params) do
    %{
      account_handle: account_handle,
      project_handle: project_handle,
      id: id
    } = conn.params

    # TODO: Add authorization check here

    case Storage.get_object(id, account_handle, project_handle) do
      {:ok, body, headers} ->
        # Set appropriate headers from S3 response
        conn = Enum.reduce(headers, conn, fn
          {"content-type", value}, acc -> put_resp_header(acc, "content-type", value)
          {"content-length", value}, acc -> put_resp_header(acc, "content-length", value)
          {"etag", value}, acc -> put_resp_header(acc, "etag", value)
          _, acc -> acc
        end)

        conn
        |> put_resp_header("content-type", "application/octet-stream")
        |> send_resp(200, body)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Artifact does not exist"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{message: "S3 error"})
    end
  end

  operation :save,
    summary: "Store CAS object",
    operation_id: "saveCasObject",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The CAS object identifier"
      ]
    ],
    request_body: {"Binary data", "application/octet-stream", nil, required: true},
    responses: %{
      204 => "Object stored successfully",
      500 => {"Server error", "application/json", Error}
    }

  def save(conn, %{id: id} = _params) do
    # Get query parameters manually since we're not using CastAndValidate for binary data
    account_handle = conn.query_params["account_handle"]
    project_handle = conn.query_params["project_handle"]

    if !account_handle || !project_handle do
      conn
      |> put_status(:bad_request)
      |> json(%{message: "Missing required query parameters: account_handle and project_handle"})
    else

    # TODO: Add authorization check here

    # Check if object already exists
    if Storage.object_exists?(id, account_handle, project_handle) do
      send_resp(conn, :no_content, "")
    else
      # Get the raw body from the connection
      body = case conn.private[:raw_body] do
        nil ->
          # Read the body if it hasn't been read yet
          {:ok, body, _conn} = Plug.Conn.read_body(conn)
          body
        raw_body ->
          raw_body
      end

      content_type = get_req_header(conn, "content-type")
        |> List.first()
        |> Kernel.||("application/octet-stream")

      case Storage.put_object(id, account_handle, project_handle, body, content_type: content_type) |> dbg do
        :ok ->
          send_resp(conn, :no_content, "")

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{message: "S3 error"})
      end
    end
    end # closing the if !account_handle || !project_handle
  end
end
