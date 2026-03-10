defmodule TuistWeb.API.UploadsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Storage
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Uploads"]

  @valid_purposes ["build_archive"]

  operation(:create,
    summary: "Create an upload.",
    operation_id: "createUpload",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Upload params", "application/json",
       %Schema{
         title: "UploadParams",
         description: "Parameters to create an upload.",
         type: :object,
         properties: %{
           id: %Schema{
             type: :string,
             format: :uuid,
             description: "Optional identifier for the upload. When provided, the upload will use this ID instead of generating one."
           },
           purpose: %Schema{
             type: :string,
             description: "The purpose of the upload.",
             enum: @valid_purposes
           },
           content_length: %Schema{
             type: :integer,
             description: "The size of the file to upload in bytes."
           }
         },
         required: [:purpose]
       }},
    responses: %{
      ok:
        {"The created upload", "application/json",
         %Schema{
           title: "Upload",
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The upload ID."},
             purpose: %Schema{type: :string, description: "The purpose of the upload."},
             upload_url: %Schema{type: :string, description: "The presigned URL to upload the file to."}
           },
           required: [:id, :purpose, :upload_url]
         }},
      unauthorized: {"You need to be authenticated to create an upload", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    purpose = body_params.purpose
    account = Authentication.authenticated_subject_account(conn)

    upload_id = Map.get(body_params, :id) || Ecto.UUID.generate()
    object_key = storage_key(selected_project.account.name, selected_project.name, purpose, upload_id)
    upload_url = Storage.generate_upload_url(object_key, account, expires_in: 3600)

    conn
    |> put_status(:ok)
    |> json(%{
      id: upload_id,
      purpose: purpose,
      upload_url: upload_url
    })
  end

  defp storage_key(account_handle, project_handle, "build_archive", upload_id) do
    "#{account_handle}/#{project_handle}/builds/#{upload_id}/build.zip"
  end
end
