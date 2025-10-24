defmodule TuistWeb.API.CASController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias Tuist.Cache.Authentication
  alias Tuist.Cache.Disk
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["CAS"]

  operation(:load,
    summary: "Download a CAS artifact.",
    operation_id: "loadCacheCAS",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The artifact identifier."
      ]
    ],
    responses: %{
      ok: {"Artifact content stream", "application/octet-stream", nil},
      not_found: {"Artifact does not exist", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def load(conn, %{id: id, account_handle: account_handle, project_handle: project_handle} = _params) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        IO.puts("CAS Controller: attempting to load #{id}")
        key = cas_key(account_handle, project_handle, id)

        if Disk.exists?(key) do
          IO.puts("CAS Controller: found #{id}")
          stream = Disk.stream(key)

          conn
          |> put_resp_content_type("application/octet-stream")
          |> send_chunked(200)
          |> stream_data(stream)
        else
          IO.puts("CAS Controller: not found #{id}")
          conn
          |> put_status(:not_found)
          |> json(%{message: "Artifact does not exist"})
        end

      {:error, status, message} ->
        IO.puts("CAS Controller: unauthorized #{id}")
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end

  defp cas_key(account_handle, project_handle, id) do
    "#{account_handle}/#{project_handle}/cas/#{id}"
  end

  defp stream_data(conn, stream) do
    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  operation(:save,
    summary: "Save a CAS artifact",
    operation_id: "saveCacheCAS",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The artifact identifier."
      ]
    ],
    request_body: {"The CAS artifact data", "application/octet-stream", nil, required: true},
    responses: %{
      no_content: {"Upload successful", nil, nil},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def save(conn, %{id: id, account_handle: account_handle, project_handle: project_handle} = _params) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        IO.puts("CAS Controller: attempting to save #{id}")
        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 100_000_000)
        key = cas_key(account_handle, project_handle, id)

        if Disk.exists?(key) do
          IO.puts("CAS Controller: already exists #{id}")
          send_resp(conn, :no_content, "")
        else
          IO.puts("CAS Controller: saving #{id}")
          Disk.put(key, body)
          IO.puts("CAS Controller: saved #{id}")
          send_resp(conn, :no_content, "")
        end

      {:error, status, message} ->
        IO.puts("CAS Controller: unauthorized #{id}")
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end
end
