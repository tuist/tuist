defmodule TuistWeb.API.CASController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias Tuist.Storage
  alias TuistWeb.API.Cache.Plugs.LoaderQueryPlug
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug LoaderQueryPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :cache

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

  def load(%{assigns: %{selected_project: project, selected_account: account}} = conn, %{id: id} = _params) do
    current_subject = Authentication.authenticated_subject(conn)
    key = cas_key(account, project, id)

    if Storage.object_exists?(key, current_subject) do
      stream = Storage.stream_object(key, current_subject)

      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_chunked(200)
      |> stream_data(stream)
    else
      conn
      |> put_status(:not_found)
      |> json(%{message: "Artifact does not exist"})
    end
  end

  defp cas_key(account, project, id) do
    "#{account.name}/#{project.name}/cas/#{id}"
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

  def save(%{assigns: %{selected_project: project, selected_account: account}} = conn, %{id: id} = _params) do
    current_subject = Authentication.authenticated_subject(conn)
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 100_000_000)
    key = cas_key(account, project, id)

    if Storage.object_exists?(key, current_subject) do
      send_resp(conn, :no_content, "")
    else
      # Stream the upload from the request body to S3
      Storage.put_object(key, body, current_subject)

      send_resp(conn, :no_content, "")
    end
  end
end
