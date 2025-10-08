defmodule TuistWeb.API.CASController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

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
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
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

  def prefix(%{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle}} = conn, _params) do
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
        prefix = "#{project.account.id}/#{project.id}/xcode/cas/"

        conn
        |> put_status(:ok)
        |> json(%{prefix: prefix})
    end
  end

  operation(:show,
    summary: "Download a CAS artifact.",
    operation_id: "getCASArtifact",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
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
      found: {"Artifact exists, redirect to presigned S3 download URL", "application/json", nil},
      not_found: {"Artifact does not exist", "application/json", nil},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def show(
        %{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => id}} = conn,
        _params
      ) do
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
        |> send_resp(:not_found, "")

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> send_resp(:not_found, "")

      Authorization.authorize(:cas_read, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to access the #{project.name} project."
        })

      true ->
        prefix = "#{project.account.id}/#{project.id}/xcode/cas/"
        key = "#{prefix}#{get_s3_key(id)}"

        if Storage.object_exists?(key, authenticated_subject) do
          url = Storage.generate_download_url(key, authenticated_subject)
          redirect(conn, external: url)
        else
          send_resp(conn, :not_found, "")
        end
    end
  end

  operation(:create,
    summary: "Upload a CAS artifact (or verify it already exists).",
    operation_id: "uploadCASArtifact",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
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
      found: {"Artifact doesn't exist, redirect to presigned S3 upload URL", "application/json", nil},
      not_modified: {"Artifact already exists, no upload needed", "application/json", nil},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def create(
        %{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => id}} = conn,
        _params
      ) do
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
        |> send_resp(:not_found, "")

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> send_resp(:not_found, "")

      Authorization.authorize(:cas_create, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to write to the #{project.name} project."
        })

      true ->
        prefix = "#{project.account.id}/#{project.id}/xcode/cas/"
        key = "#{prefix}#{get_s3_key(id)}"

        if Storage.object_exists?(key, authenticated_subject) do
          send_resp(conn, :not_modified, "")
        else
          url = Storage.generate_upload_url(key, authenticated_subject)
          redirect(conn, external: url)
        end
    end
  end

  # Convert CAS ID to S3 key format by replacing ~ with /
  # Format: {version}~{hash} -> {version}/{hash}
  # Example: 0~YWoYNXX... -> 0/YWoYNXX...
  defp get_s3_key(cas_id) do
    String.replace(cas_id, "~", "/")
  end
end
