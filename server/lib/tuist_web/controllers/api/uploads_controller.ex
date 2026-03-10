defmodule TuistWeb.API.UploadsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Storage
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadCompletion
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadPart
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadParts
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistWeb.API.Schemas.ArtifactUploadId
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

  operation(:multipart_start,
    summary: "Start a multipart upload.",
    operation_id: "startUploadsMultipartUpload",
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
      {"Multipart upload start params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           id: %Schema{
             type: :string,
             format: :uuid,
             description: "The identifier for the upload."
           },
           purpose: %Schema{
             type: :string,
             description: "The purpose of the upload.",
             enum: @valid_purposes
           }
         },
         required: [:purpose, :id]
       }},
    responses: %{
      ok: {"The multipart upload has been started", "application/json", ArtifactUploadId},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_start(
        %{assigns: %{selected_project: selected_project}, body_params: body_params} = conn,
        _params
      ) do
    account = Authentication.authenticated_subject_account(conn)
    upload_id = body_params.id
    object_key = storage_key(selected_project.account.name, selected_project.name, body_params.purpose, upload_id)

    multipart_upload_id = Storage.multipart_start(object_key, account)

    json(conn, %{status: "success", data: %{upload_id: multipart_upload_id}})
  end

  operation(:multipart_generate_url,
    summary: "Generate a signed URL for uploading a part.",
    description:
      "Given an upload ID and a part number, this endpoint returns a signed URL that can be used to upload a part of a multipart upload.",
    operation_id: "generateUploadsMultipartUploadURL",
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
      {"Artifact to generate a signed URL for", "application/json",
       %Schema{
         type: :object,
         properties: %{
           id: %Schema{
             type: :string,
             format: :uuid,
             description: "The identifier for the upload."
           },
           purpose: %Schema{
             type: :string,
             description: "The purpose of the upload.",
             enum: @valid_purposes
           },
           multipart_upload_part: ArtifactMultipartUploadPart
         },
         required: [:purpose, :id, :multipart_upload_part]
       }},
    responses: %{
      ok: {"The URL has been generated", "application/json", ArtifactMultipartUploadUrl},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{
            id: upload_id,
            purpose: purpose,
            multipart_upload_part: %{part_number: part_number, upload_id: multipart_upload_id} = multipart_upload_part
          }
        } = conn,
        _params
      ) do
    content_length = Map.get(multipart_upload_part, :content_length)
    object_key = storage_key(selected_project.account.name, selected_project.name, purpose, upload_id)

    url =
      Storage.multipart_generate_url(
        object_key,
        multipart_upload_id,
        part_number,
        selected_project.account,
        expires_in: 120,
        content_length: content_length
      )

    json(conn, %{status: "success", data: %{url: url}})
  end

  operation(:multipart_complete,
    summary: "Complete a multipart upload.",
    description:
      "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload.",
    operation_id: "completeUploadsMultipartUpload",
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
      {"Upload multipart upload completion", "application/json",
       %Schema{
         type: :object,
         properties: %{
           id: %Schema{
             type: :string,
             format: :uuid,
             description: "The identifier for the upload."
           },
           purpose: %Schema{
             type: :string,
             description: "The purpose of the upload.",
             enum: @valid_purposes
           },
           multipart_upload_parts: ArtifactMultipartUploadParts
         },
         required: [:purpose, :id, :multipart_upload_parts]
       }},
    responses: %{
      ok: {"The upload has been completed", "application/json", ArtifactMultipartUploadCompletion},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{
            id: upload_id,
            purpose: purpose,
            multipart_upload_parts: %ArtifactMultipartUploadParts{parts: parts, upload_id: multipart_upload_id}
          }
        } = conn,
        _params
      ) do
    object_key = storage_key(selected_project.account.name, selected_project.name, purpose, upload_id)

    :ok =
      Storage.multipart_complete_upload(
        object_key,
        multipart_upload_id,
        Enum.map(parts, fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end),
        selected_project.account
      )

    json(conn, %{status: "success", data: %{}})
  end

  defp storage_key(account_handle, project_handle, "build_archive", upload_id) do
    "#{account_handle}/#{project_handle}/builds/#{upload_id}/build.zip"
  end
end
