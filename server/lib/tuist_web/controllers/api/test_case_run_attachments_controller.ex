defmodule TuistWeb.API.TestCaseRunAttachmentsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  operation(:create,
    summary: "Create a test case run attachment and get a presigned upload URL.",
    operation_id: "createTestCaseRunAttachment",
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
    request_body:
      {"Attachment params", "application/json",
       %Schema{
         title: "TestCaseRunAttachmentParams",
         type: :object,
         properties: %{
           test_case_run_id: %Schema{
             type: :string,
             description: "The UUID of the test case run."
           },
           file_name: %Schema{
             type: :string,
             description: "The file name of the attachment."
           }
         },
         required: [:test_case_run_id, :file_name]
       }},
    responses: %{
      created:
        {"The attachment was created", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The attachment ID."},
             upload_url: %Schema{type: :string, description: "Presigned URL to upload the file."},
             expires_at: %Schema{type: :integer, description: "Unix timestamp when the upload URL expires."}
           },
           required: [:id, :upload_url, :expires_at]
         }},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"Not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: project}, body_params: body_params} = conn, _params) do
    attachment_id = UUIDv7.generate()

    attrs = %{
      id: attachment_id,
      test_case_run_id: body_params.test_case_run_id,
      file_name: body_params.file_name,
      inserted_at: NaiveDateTime.utc_now()
    }

    {:ok, _attachment} = Tests.create_test_case_run_attachment(attrs)

    expires_in = 3600

    s3_object_key =
      Tests.attachment_storage_key(%{
        account_handle: project.account.name,
        project_handle: project.name,
        test_case_run_id: body_params.test_case_run_id,
        attachment_id: attachment_id,
        file_name: body_params.file_name
      })

    upload_url =
      Storage.generate_upload_url(s3_object_key, project.account, expires_in: expires_in)

    conn
    |> put_status(:created)
    |> json(%{
      id: attachment_id,
      upload_url: upload_url,
      expires_at: System.system_time(:second) + expires_in
    })
  end
end
