defmodule TuistWeb.API.TestCaseRunAttachmentsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.InstrumentedCastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  operation(:index,
    summary: "List attachments for a test case run.",
    operation_id: "listTestCaseRunAttachments",
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
      test_case_run_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test case run."
      ]
    ],
    responses: %{
      ok:
        {"List of attachments", "application/json",
         %Schema{
           type: :object,
           properties: %{
             test_case_run_id: %Schema{type: :string, format: :uuid, description: "The test case run ID."},
             attachments: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The attachment ID."},
                   file_name: %Schema{type: :string, description: "The file name."},
                   type: %Schema{type: :string, description: "The attachment type."},
                   download_url: %Schema{type: :string, description: "Presigned download URL."}
                 },
                 required: [:id, :file_name, :type, :download_url]
               }
             }
           },
           required: [:test_case_run_id, :attachments]
         }},
      not_found: {"Test case run not found", "application/json", Error},
      forbidden: {"Not authorized to perform this action", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: project}, params: %{test_case_run_id: test_case_run_id}} = conn, _params) do
    case Tests.get_test_case_run_by_id(test_case_run_id, project_id: project.id, preload: [:attachments]) do
      {:ok, %{project_id: project_id} = run} when project_id == project.id ->
        attachments =
          Enum.map(run.attachments, fn attachment ->
            key =
              Tests.attachment_storage_key(%{
                account_handle: project.account.name,
                project_handle: project.name,
                test_case_run_id: test_case_run_id,
                attachment_id: attachment.id,
                file_name: attachment.file_name
              })

            download_url = Storage.generate_download_url(key, project.account, expires_in: 3600)

            %{
              id: attachment.id,
              file_name: attachment.file_name,
              type: attachment_type(attachment.file_name),
              download_url: download_url
            }
          end)

        json(conn, %{
          test_case_run_id: test_case_run_id,
          attachments: attachments
        })

      _error ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test case run not found."})
    end
  end

  defp attachment_type(file_name) do
    ext = file_name |> Path.extname() |> String.downcase()

    case ext do
      ext when ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"] -> "image"
      ".txt" -> "text"
      ".log" -> "log"
      ".json" -> "json"
      ".xml" -> "xml"
      ".csv" -> "csv"
      ".ips" -> "crash_report"
      _ -> "file"
    end
  end

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
           },
           repetition_number: %Schema{
             type: :integer,
             nullable: true,
             description: "The repetition number (attempt) this attachment belongs to."
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

    attrs =
      then(
        %{
          id: attachment_id,
          test_case_run_id: body_params.test_case_run_id,
          file_name: body_params.file_name,
          inserted_at: NaiveDateTime.utc_now()
        },
        fn attrs ->
          case Map.get(body_params, :repetition_number) do
            nil -> attrs
            repetition_number -> Map.put(attrs, :repetition_number, repetition_number)
          end
        end
      )

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
