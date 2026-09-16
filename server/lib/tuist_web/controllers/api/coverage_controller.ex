defmodule TuistWeb.API.CoverageController do
  @moduledoc """
  What a client needs to send a run's code coverage when it processed the
  bundle itself: the size above which the coverage goes to object storage
  rather than inline with the run, and a signed URL to put it there.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Tests.Coverage
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  @path_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]

  operation(:settings,
    summary: "Get the code coverage upload settings for a project.",
    description:
      "The size, in bytes of the DEFLATE-compressed coverage, above which a client that processed the result bundle itself uploads the coverage to object storage (see `createCoverageUpload`) instead of sending it inline with the test run.",
    operation_id: "getCoverageSettings",
    parameters: @path_parameters,
    responses: %{
      ok:
        {"The settings", "application/json",
         %Schema{
           title: "CoverageSettings",
           type: :object,
           properties: %{
             inline_threshold_bytes: %Schema{
               type: :integer,
               description: "Compressed coverage larger than this goes through an upload."
             }
           },
           required: [:inline_threshold_bytes]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def settings(conn, _params) do
    json(conn, %{inline_threshold_bytes: Environment.coverage_inline_threshold_bytes()})
  end

  operation(:create_upload,
    summary: "Get a signed URL to upload a test run's code coverage.",
    description:
      "Returns where to PUT the DEFLATE-compressed coverage file (one JSON object per source file, as the client's parser writes it) for a test run the client is about to create with the given id. The run then references it through `xcode_coverage_storage_key`, and the server reads it back once the run exists.",
    operation_id: "createCoverageUpload",
    parameters: @path_parameters,
    request_body:
      {"The run the coverage belongs to", "application/json",
       %Schema{
         title: "CoverageUploadRequest",
         type: :object,
         properties: %{
           test_run_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The client-generated id of the test run the coverage belongs to."
           }
         },
         required: [:test_run_id]
       }},
    responses: %{
      ok:
        {"Where to upload the coverage", "application/json",
         %Schema{
           title: "CoverageUpload",
           type: :object,
           properties: %{
             storage_key: %Schema{
               type: :string,
               description: "The key to send with the run as `xcode_coverage_storage_key`."
             },
             upload_url: %Schema{type: :string, description: "A short-lived URL to PUT the compressed coverage to."}
           },
           required: [:storage_key, :upload_url]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def create_upload(%{assigns: %{selected_project: project}, body_params: %{test_run_id: test_run_id}} = conn, _params) do
    storage_key = Coverage.storage_key(project, test_run_id)
    json(conn, %{storage_key: storage_key, upload_url: Storage.generate_upload_url(storage_key, project.account)})
  end
end
