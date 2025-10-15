defmodule TuistWeb.API.CASController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Projects
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

  operation(:prefix,
    summary: "Get the S3 object key prefix for a project's CAS storage.",
    operation_id: "getCASPrefix",
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
      ]
    ],
    responses: %{
      ok:
        {"The CAS storage prefix", "application/json",
         %Schema{
           type: :object,
           properties: %{
             prefix: %Schema{
               type: :string,
               description: "The S3 object key prefix where CAS objects should be stored.",
               example: "account-123/project-456/xcode/cas/"
             }
           },
           required: [:prefix]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def prefix(conn, _params) do
    %{account_handle: account_handle, project_handle: project_handle} = conn.private.open_api_spex.params
    authenticated_subject = Authentication.authenticated_subject(conn)
    account = Accounts.get_account_by_handle(account_handle)

    project =
      if is_nil(account),
        do: nil,
        else: Projects.get_project_by_account_and_project_handles(account.name, project_handle, preload: [:account])

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Account #{account_handle} not found."})

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project #{account_handle}/#{project_handle} not found."})

      Authorization.authorize(:cas_read, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to access the #{project.name} project."
        })

      true ->
        prefix = "#{project.account.name}/#{project.name}/cas/"

        conn
        |> put_status(:ok)
        |> json(%{prefix: prefix})
    end
  end

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
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
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
      ok:
        {"Upload successful", "application/json",
         %Schema{type: :object, title: "CASArtifact", properties: %{id: %Schema{type: :string}}}},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def save(%{assigns: %{selected_project: project, selected_account: account}} = conn, %{id: id} = _params) do
    current_subject = Authentication.authenticated_subject(conn)
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 100_000_000)
    key = cas_key(account, project, id)

    if Storage.object_exists?(key, current_subject) do
      conn
      |> put_status(:ok)
      |> json(%{id: "key"})
    else
      # Stream the upload from the request body to S3
      Storage.put_object(key, body, current_subject)

      conn
      |> put_status(:ok)
      |> json(%{id: key})
    end
  end
end
